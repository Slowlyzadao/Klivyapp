# Auditoria — Aba "Exames e Imagens" (plugins/patients)

**Data:** 2026-04-26
**Escopo:** módulo `plugins/patients` → aba "Exames e Imagens"
**Status:** plano de fixes aprovado, dados de teste apenas (sem arquivos reais de pacientes)
**Contexto:** Como ainda estamos em fase de testes e não há arquivos reais de clientes, podemos realizar mudanças que invalidem uploads existentes sem necessidade de migração de dados.

---

## ⚠️ Resumo executivo

O módulo tem **8 bugs críticos** que se reforçam mutuamente. A causa raiz dos três sintomas reportados (pastas não persistem, vídeo quebra, render inconsistente) está em **três lugares diferentes do pipeline**, todos individualmente fáceis de corrigir mas escondidos pelo tamanho do `Record.vue` (12k linhas) e pela coexistência de **duas implementações concorrentes** de pastas (uma JSONB, uma relacional).

---

## 1. Diagnóstico — bugs encontrados

### 🔴 CRÍTICO

| # | Bug | Local | Sintoma para o usuário |
|---|-----|-------|------------------------|
| **C1** | Pastas não persistem por mismatch de wrapped params | `plugins/patients/app/controllers/api/v1/accounts/patients/exam_folders_controller.rb:21-28` + `plugins/patients/frontend/api/patients/examFolders.js:21-25` | "Pastas somem após F5" |
| **C2** | Vídeos renderizados como `<img>`, sem tag `<video>` | `Record.vue:7909-7913` e lightbox `12108-12115` | "Vídeo enviou mas não abre" |
| **C3** | Duas implementações concorrentes de pastas: tabela `exam_folders` + JSONB `exam_folder_data` | `exam_folder.rb` vs `exam_folders_controller.rb:11` | Confusão arquitetural; coluna `exam_folder_id` em `exam_medias` órfã |
| **C4** | Strong params filtra `parentId`/`order` (camelCase) que o frontend envia | `exam_folders_controller.rb:23` | Mesmo se C1 for corrigido, hierarquia/ordem das pastas é descartada |
| **C5** | Limites de tamanho não são aplicados no backend por tipo de mídia | `exam_media.rb:135-137` (aceita até 500MB) | "Storage vai inflar" — vídeos grandes passam |

### 🟡 MÉDIO

| # | Bug | Local | Impacto |
|---|-----|-------|---------|
| **M1** | `signed_url` usa `host: 'localhost:3000'` como fallback | `exam_media.rb:75` | URLs quebradas se `default_url_options[:host]` não estiver configurado em produção |
| **M2** | `expires_in: 15.minutes` na URL é incompatível com galerias/lightbox revisitados | `exam_media.rb:68` | Imagem aberta após 15min volta 404 |
| **M3** | Frontend não exibe limites/tipos aceitos antes do upload | `Record.vue:7443` | Usuário tenta arquivos não suportados |
| **M4** | `exam_folder_data` é apagado em qualquer save (zera `folders`/`expanded_ids` por causa de C1) | `exam_folders_controller.rb:32-43` | Mesmo o `media_folder_map` que "funciona" via beacon pode regredir |
| **M5** | `category` é detectada apenas pelo MIME do navegador (não-confiável) | `Record.vue:1268-1274` | iPhone HEIC → cai em `outro`; vídeo `.mov` no Windows → MIME vazio → `outro` |
| **M6** | Lock/unlock usa **PIN hardcoded `'123'`** no frontend | `Record.vue:327` | Falsa sensação de segurança; bypass trivial |
| **M7** | `exam_folder_id` (FK) e `locked` (bool) em `exam_medias` foram migrados mas **nunca usados** pelo controller | `db/migrate/20260322200003_add_folder_and_lock_to_exam_medias.rb` | Schema sujo |

### 🟢 BAIXO

| # | Bug | Local |
|---|-----|-------|
| **B1** | `ExamsTab.vue` é um arquivo template **órfão** (897 linhas duplicadas dentro de Record.vue, sem `<script>`) | `plugins/patients/frontend/routes/patients/tabs/ExamsTab.vue` |
| **B2** | Categoria `pdf?` exige `category == 'laudo'` mas qualquer PDF que vier como `outro` retorna `false` | `exam_media.rb:89-91` |
| **B3** | Sem `dependent: :destroy` em `has_one_attached :file` quando `soft_delete!` — blob fica órfão para sempre (acumulando custo S3) | `exam_media.rb:7` |
| **B4** | Sem variants/thumbnails para imagens — galeria carrega o arquivo full em cada card | `Record.vue:7909-7913` |
| **B5** | Sem CSP/CORS-aware `disposition: :inline` para vídeo (S3 com Content-Type errado quebra streaming) | `exam_media.rb:68` |

---

## 2. Explicação detalhada dos bugs críticos

### C1 — A causa raiz de "pastas não persistem"

Frontend envia (axios, `examFolders.js:22-24`):

```js
axios.put(`${baseUrl(patientId)}/${folderId}`, { exam_folder: data });
// data = { folders: [...], lock_map: {}, expanded_ids: [], media_folder_map: {} }
```

Body real: `{"exam_folder": {"folders": [...], "lock_map": {}, ...}}`

Backend (`exam_folders_controller.rb:21-28`):

```ruby
def folder_data_params
  params.permit(
    folders: [:id, :name, :color, :isRoot, :parent_id, :position],
    lock_map: {}, media_folder_map: {}, expanded_ids: []
  ).to_h
end
```

`params.permit(folders: [...])` lê `params[:folders]`. **Mas o frontend envolveu tudo em `exam_folder`**, e o `wrap_parameters` do Rails detecta que a chave já existe e não desempacota. Logo `params[:folders]` é `nil`, e o controller persiste um blob praticamente vazio. F5 → tudo perdido.

> Curiosidade: o caminho `sendBeacon` de `Record.vue:374-378` envia `{folders, lock_map, ...}` **sem** o wrapper `exam_folder`, então o ParamsWrapper auto-encapsula e `params[:folders]` fica disponível. Por isso parece "funcionar às vezes" — só funciona quando o usuário **fecha a aba**, nunca quando dá F5.

### C2 — Vídeo nunca renderiza

Galeria (`Record.vue:7909-7929`):

```html
<img v-if="media.url && !media.mime_type?.includes('pdf')" :src="media.url" />
<div v-else-if="media.mime_type?.includes('pdf') ...">PDF</div>
<i v-else class="i-lucide-image" />
```

MP4 não tem `'pdf'` no mime → vai para o `<img>` → quebra. Mesmo problema no lightbox (`12108-12115`).

O upload em si funciona — `ALLOWED_CONTENT_TYPES` aceita `video/mp4 video/quicktime video/x-msvideo video/webm` (`exam_media.rb:34-40`).

### C3 — Dois sistemas de pastas concorrentes

- Migration relacional (`20260322200003`): cria `exam_folders` (`patient_id`, `account_id`, `name`, `parent_id`, `position`) + adiciona `exam_folder_id` em `exam_medias`.
- Migration JSONB (`20260322200005`): adiciona `patients.exam_folder_data` jsonb.
- Model `ExamFolder` existe — **mas o controller usa só o JSONB** (`exam_folders_controller.rb:11`).

Resultado: tabela `exam_folders` está sempre vazia, FK `exam_folder_id` em `exam_medias` está sempre nula, e a "verdade" das pastas vive num blob frágil que o Rails reseta a cada PUT (C1).

### C4 — camelCase × snake_case

Frontend envia `parentId` e `order` (`Record.vue:642-643`, `619-621`). Strong params permite `parent_id` e `position`. Mesmo após corrigir C1, drag-and-drop e nesting nunca persistirão.

### C5 — Sem limites por tipo

`exam_media.rb:135-137`:

```ruby
return unless file.byte_size > 500.megabytes
errors.add(:file, :too_large, message: 'arquivo muito grande (máximo 500MB)')
```

Vídeo de 200MB passa direto. Requisito era 10MB para vídeo, 5MB imagem, 10MB PDF.

---

## 3. Correções propostas — código pronto

### Fix C1+C4 — Controller de pastas que realmente persiste

`plugins/patients/app/controllers/api/v1/accounts/patients/exam_folders_controller.rb`:

```ruby
class Api::V1::Accounts::Patients::ExamFoldersController < Api::V1::Accounts::BaseController
  wrap_parameters false                       # evita ambiguidade com wrap_parameters global
  before_action :set_patient

  def index
    render json: (@patient.exam_folder_data.presence || default_blob)
  end

  # PUT /exam_folders/bulk  (rota mantida — :id é ignorado)
  def update
    @patient.update!(exam_folder_data: sanitized_blob)
    render json: @patient.exam_folder_data
  end

  private

  def set_patient
    @patient = Current.account.patients.find(params[:patient_id])
  end

  def default_blob
    { 'folders' => [], 'lock_map' => {}, 'media_folder_map' => {}, 'expanded_ids' => [] }
  end

  # Aceita tanto { folders: [...] } (sendBeacon) quanto { exam_folder: { folders: [...] } } (axios)
  def raw_payload
    src = params[:exam_folder].present? ? params[:exam_folder] : params
    src.permit(
      folders: %i[id name color isRoot parent_id parentId position order],
      lock_map: {}, media_folder_map: {}, expanded_ids: []
    ).to_h
  end

  def sanitized_blob
    raw       = raw_payload
    valid_ids = @patient.exam_medias.active.pluck(:id).map(&:to_s).to_set

    folders = (raw['folders'] || []).map do |f|
      {
        'id'        => f['id'],
        'name'      => f['name'].to_s.strip[0, 80],
        'color'     => f['color'].presence || '#60a5fa',
        'isRoot'    => f['isRoot'] == true,
        'parent_id' => f['parent_id'] || f['parentId'],
        'position'  => (f['position'] || f['order']).to_i,
      }
    end.reject { |f| f['name'].blank? }

    {
      'folders'          => folders,
      'expanded_ids'     => Array(raw['expanded_ids']).map(&:to_s),
      'media_folder_map' => (raw['media_folder_map'] || {}).select { |mid, _| valid_ids.include?(mid.to_s) },
      'lock_map'         => (raw['lock_map']         || {}).select { |mid, _| valid_ids.include?(mid.to_s) }
    }
  end
end
```

> **Nota:** essa correção é um *band-aid* compatível com o blob JSONB atual. A solução estrutural correta é migrar para o modelo relacional `ExamFolder` (ver seção 4). Como ainda estamos em testes, dá para pular direto para a solução estrutural.

### Fix C2 — Renderização de vídeo

Galeria (`Record.vue:7907-7937`):

```html
<div class="exams-thumb" @click="openMediaLightbox(media)">
  <video
    v-if="isVideo(media)"
    :src="media.url"
    class="object-cover w-full h-full"
    preload="metadata"
    muted
    playsinline
  />
  <img
    v-else-if="isImage(media)"
    :src="media.url"
    class="object-cover w-full h-full"
    loading="lazy"
  />
  <div v-else-if="isPdf(media)" class="exams-thumb-pdf">…</div>
  <i v-else class="i-lucide-file text-slate-600 text-4xl" />
</div>
```

Lightbox (`12094-12116`):

```html
<div class="flex-1 flex items-center justify-center p-4 overflow-hidden">
  <iframe v-if="isPdf(lightboxMedia)" :src="lightboxMedia.url" class="w-full h-full rounded-lg bg-white" />
  <video
    v-else-if="isVideo(lightboxMedia)"
    :src="lightboxMedia.url"
    class="max-w-full max-h-full rounded-lg"
    controls
    autoplay
    playsinline
  />
  <img v-else :src="lightboxMedia.url" class="max-w-full max-h-full object-contain rounded-lg" />
</div>
```

Helpers (perto de `mediasInFolder` em Record.vue ~430):

```js
const isVideo = (m) => (m?.mime_type || '').startsWith('video/')
  || /\.(mp4|mov|webm|avi|mkv)$/i.test(m?.file_name || '');
const isPdf = (m) => (m?.mime_type || '').includes('pdf')
  || /\.pdf$/i.test(m?.file_name || '');
const isImage = (m) => (m?.mime_type || '').startsWith('image/')
  || /\.(jpe?g|png|gif|webp|heic|heif)$/i.test(m?.file_name || '');
```

### Fix C5+M5 — Limites por tipo no backend

`plugins/patients/app/models/exam_media.rb` (substituir blocos `ALLOWED_CONTENT_TYPES` e `file_content_type_and_size`):

```ruby
SIZE_LIMITS = {
  image: 5.megabytes,
  pdf:   10.megabytes,
  video: 10.megabytes,
}.freeze

IMAGE_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif image/gif].freeze
PDF_TYPES   = %w[application/pdf].freeze
VIDEO_TYPES = %w[video/mp4 video/quicktime video/webm].freeze
ALLOWED_CONTENT_TYPES = (IMAGE_TYPES + PDF_TYPES + VIDEO_TYPES).freeze

def file_kind
  ct = file.content_type.to_s
  return :image if IMAGE_TYPES.include?(ct)
  return :pdf   if PDF_TYPES.include?(ct)
  return :video if VIDEO_TYPES.include?(ct)
  :unknown
end

def file_content_type_and_size
  return unless file.attached?

  unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
    errors.add(:file, "formato não suportado (#{file.content_type})")
    return
  end

  kind  = file_kind
  limit = SIZE_LIMITS[kind]
  if limit && file.byte_size > limit
    human = ActiveSupport::NumberHelper.number_to_human_size(limit)
    errors.add(:file, "arquivo muito grande para #{kind} (máx. #{human})")
  end
end
```

E auto-derive `category` a partir do `file_kind` (não confie no client):

```ruby
before_validation :derive_category_from_file, on: :create

def derive_category_from_file
  return unless file.attached?
  case file_kind
  when :video then self.category ||= 'video'
  when :pdf   then self.category ||= 'laudo'
  when :image then self.category ||= 'foto_clinica'
  else             self.category ||= 'outro'
  end
end
```

### Fix M1+M2 — `signed_url` correto

`exam_media.rb:67-79`:

```ruby
def signed_url(expires_in: 1.hour, disposition: :inline)
  return nil unless file.attached?

  Rails.application.routes.url_helpers.rails_blob_url(
    file,
    expires_in: expires_in,
    disposition: disposition
    # NÃO passe host aqui — confie em config.active_storage.default_url_options
  )
end
```

Garanta em `config/environments/production.rb`:

```ruby
config.active_storage.default_url_options = { host: ENV.fetch('FRONTEND_URL'), protocol: 'https' }
```

### Fix B3 — Soft-delete + purge agendado

```ruby
def soft_delete!
  update!(deleted_at: Time.current)
  ::Patients::ExamMediaPurgeJob.set(wait: 30.days).perform_later(id)
end
```

Job:

```ruby
class Patients::ExamMediaPurgeJob < ApplicationJob
  def perform(exam_media_id)
    media = ExamMedia.deleted.find_by(id: exam_media_id)
    return unless media
    media.file.purge_later
    media.destroy!
  end
end
```

---

## 4. Estrutura ideal de pastas (recomendação estrutural)

A coexistência de JSONB + tabela relacional é dívida técnica que vai escalar mal (busca por pasta, contagens, paginação, índices). **Como ainda estamos em testes**, recomendação: **migrar direto para o modelo relacional já existente** (`ExamFolder`) e usar `exam_medias.exam_folder_id` que já está migrado. Sem necessidade de migração de dados.

```ruby
# ExamFolder
class ExamFolder < ApplicationRecord
  belongs_to :account
  belongs_to :patient
  belongs_to :parent, class_name: 'ExamFolder', optional: true
  has_many   :children, class_name: 'ExamFolder', foreign_key: :parent_id, dependent: :destroy
  has_many   :exam_medias, dependent: :nullify

  validates :name, presence: true, length: { maximum: 80 }
  validates :patient_id, presence: true
  validates :account_id, presence: true
  validate  :max_one_level_nesting
  validate  :no_circular_parent

  scope :ordered, -> { order(:position, :id) }

  private
  def max_one_level_nesting
    errors.add(:parent_id, 'subpastas não podem conter subpastas') if parent&.parent_id.present?
  end
  def no_circular_parent
    return unless parent_id && parent_id == id
    errors.add(:parent_id, 'pasta não pode ser pai de si mesma')
  end
end
```

Controller migrado (substituir o JSONB):

```ruby
class Api::V1::Accounts::Patients::ExamFoldersController < Api::V1::Accounts::BaseController
  before_action :set_patient
  before_action :set_folder, only: %i[update destroy]

  def index
    folders = @patient.exam_folders.includes(:children).ordered
    render json: folders.as_json(only: %i[id name color parent_id position])
  end

  def create
    folder = @patient.exam_folders.build(folder_params.merge(account: Current.account))
    folder.save!
    render json: folder, status: :created
  end

  def update
    @folder.update!(folder_params)
    render json: @folder
  end

  def destroy
    @folder.exam_medias.update_all(exam_folder_id: nil)
    @folder.destroy!
    head :no_content
  end

  # PUT /exam_folders/reorder — payload: [{id, position, parent_id}, ...]
  def reorder
    ActiveRecord::Base.transaction do
      Array(params[:items]).each do |item|
        @patient.exam_folders.where(id: item[:id]).update_all(
          parent_id: item[:parent_id], position: item[:position].to_i
        )
      end
    end
    head :ok
  end

  private
  def set_patient
    @patient = Current.account.patients.find(params[:patient_id])
  end
  def set_folder
    @folder = @patient.exam_folders.find(params[:id])
  end
  def folder_params
    params.require(:exam_folder).permit(:name, :color, :parent_id, :position)
  end
end
```

E adicione ao `ExamMediasController#exam_update_params`:

```ruby
def exam_update_params
  params.permit(:category, :description, :exam_folder_id, :locked, tags: [])
end
```

**Limpeza pós-migração** (já que estamos em teste):
- Remover coluna `patients.exam_folder_data` (migration nova).
- Remover model `Patient` qualquer referência ao blob.
- Remover lógica de `mediaFolderMap`, `lockMap`, `expanded_ids` no JSONB no frontend; substituir por chamadas REST por pasta.

---

## 5. Segurança & Multi-tenant (revisão)

### ✅ O que está correto
- `set_patient` em ambos controllers usa `Current.account.patients.find` → **isolamento OK**.
- `exam_medias` tem `account_id` indexado, `set_exam_media` re-escopa via `@patient.exam_medias.active.find` → **OK**.
- `signed_url` usa expires_in (não é URL pública) → **OK**.

### ⚠️ Pontos a reforçar
1. **ActiveStorage path não inclui `account_id`**. Por padrão `key` é UUID aleatório — não há colisão, mas é impossível auditar sem referência cruzada. Considere tag custom no S3 (`x-amz-meta-account-id`).
2. **`compare` action** (`exam_medias_controller.rb:93-118`) faz `find` em ambos IDs já escopado por paciente → **OK**.
3. **`signed_url` usa rota Rails padrão** — em produção atrás de Cloudflare/CDN, considere `expires_in: 1.hour` mínimo e direct-to-S3 signed URL para evitar streaming pelo Rails.
4. **PIN `'123'` hardcoded** (`Record.vue:327`) — mover para policy server-side ou remover a "feature".

---

## 6. UX — melhorias mínimas

### Mensagem clara antes do upload
Adicionar em `Record.vue ~7438` (perto do botão Upload):

```html
<p class="text-xs text-slate-500 mt-2">
  Aceitos: imagens (JPG, PNG, WEBP, HEIC) até 5MB · PDF até 10MB · vídeo (MP4, MOV, WEBM) até 10MB
</p>
```

### Validação no client antes de bater no servidor

```js
const SIZE_LIMITS = { image: 5*1024*1024, pdf: 10*1024*1024, video: 10*1024*1024 };
const ACCEPTED = {
  image: /^image\/(jpeg|png|gif|webp|heic|heif)$/,
  pdf:   /^application\/pdf$/,
  video: /^video\/(mp4|quicktime|webm)$/,
};
const classify = (f) => {
  if (ACCEPTED.image.test(f.type)) return 'image';
  if (ACCEPTED.pdf.test(f.type))   return 'pdf';
  if (ACCEPTED.video.test(f.type)) return 'video';
  return null;
};

const onMediaFileSelected = async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  const kind = classify(file);
  if (!kind) {
    useAlert('Formato não suportado. Use imagem, PDF ou vídeo (MP4/MOV/WEBM).');
    event.target.value = null; return;
  }
  if (file.size > SIZE_LIMITS[kind]) {
    const mb = SIZE_LIMITS[kind] / 1024 / 1024;
    useAlert(`Arquivo muito grande. Máximo ${mb}MB para ${kind}.`);
    event.target.value = null; return;
  }
  // ... resto igual
};
```

---

## 7. Otimização de imagens (futuro, não bloqueante)

```ruby
# exam_media.rb
def thumbnail_url
  return nil unless image? && file.attached?
  Rails.application.routes.url_helpers.rails_representation_url(
    file.variant(resize_to_limit: [400, 400]).processed,
    expires_in: 1.hour
  )
end
```

Use `thumbnail_url` no jbuilder em `_exam_media.json.jbuilder` para o card e `signed_url` no lightbox.

Para vídeo, gerar poster (frame estático) com `streamio-ffmpeg`:

```ruby
class GenerateVideoPosterJob < ApplicationJob
  def perform(exam_media_id)
    media = ExamMedia.find(exam_media_id)
    return unless media.video?
    # extrai frame e anexa como variant ou attachment separado
  end
end
```

---

## 8. Plano de ataque recomendado

> Como **não há arquivos reais** ainda, podemos limpar storage de teste e fazer mudanças destrutivas em uploads sem migração de dados.

### Fase 1 — Fixes visíveis ao usuário (1 dia)

1. **Fix C2** (vídeo no `<video>`): 30 min, 0 risco — corrige o sintoma mais visível imediatamente.
2. **Fix C5+M5** (limites por tipo + auto-derive category): 1h, médio risco. Vai invalidar uploads existentes (que já são teste).
3. **Fix M1+M2** (`signed_url` sem fallback localhost + `expires_in: 1.hour`): 10 min, 0 risco.
4. **Fix M3+UX** (mensagens de tipo/tamanho + validação client-side): 30 min.

### Fase 2 — Refactor estrutural (1-2 dias)

5. **C3 + C1 + C4 — Migração JSONB → relacional**: PR separado.
   - Substitui controller para usar `ExamFolder` AR.
   - Atualiza frontend para REST por pasta (CRUD individual + reorder).
   - Remove `patients.exam_folder_data` (migration de drop).
   - Remove arquivo órfão `ExamsTab.vue` (B1).

### Fase 3 — Cleanup e otimização (depois)

6. **B3** (purge job de soft delete).
7. **B4** (variants/thumbnails).
8. **M6** (PIN server-side ou remover lock feature).
9. Limpeza do `Record.vue` (12k linhas → componentizar).

---

## 9. Checklist de teste manual pós-fix

Após cada fase, validar manualmente:

### Pastas
- [ ] Criar pasta "Fotos" → F5 → pasta persiste
- [ ] Renomear pasta + cor → F5 → persiste
- [ ] Mover arquivo para pasta → F5 → arquivo na pasta
- [ ] Criar subpasta (drag) → F5 → hierarquia persiste
- [ ] Tentar criar subpasta dentro de subpasta → bloqueado
- [ ] Excluir pasta com arquivos → arquivos voltam para raiz
- [ ] Tentar acessar pasta de outro tenant → 404 (multi-tenant)

### Upload
- [ ] Upload imagem JPG até 5MB → sucesso
- [ ] Upload imagem 6MB → erro claro com limite
- [ ] Upload PDF até 10MB → sucesso
- [ ] Upload PDF 11MB → erro claro
- [ ] Upload vídeo MP4 até 10MB → sucesso
- [ ] Upload vídeo MP4 11MB → erro claro
- [ ] Upload arquivo `.exe` → erro claro de formato
- [ ] Upload `.heic` do iPhone → categoriza como `foto_clinica`

### Renderização
- [ ] Vídeo aparece com player (não `<img>` quebrado)
- [ ] Vídeo no lightbox tem controles (play, volume, fullscreen)
- [ ] PDF abre em iframe
- [ ] Imagem abre em alta resolução no lightbox
- [ ] Thumbnail de imagem usa variant pequeno (Fase 3)

### Multi-tenant
- [ ] URL assinada de outro tenant → 404
- [ ] Listagem só retorna arquivos do tenant atual
- [ ] `compare` rejeita IDs de outro paciente

---

## 10. Referências de arquivos auditados

- `plugins/patients/app/models/exam_media.rb`
- `plugins/patients/app/models/exam_folder.rb`
- `plugins/patients/app/controllers/api/v1/accounts/patients/exam_medias_controller.rb`
- `plugins/patients/app/controllers/api/v1/accounts/patients/exam_folders_controller.rb`
- `plugins/patients/frontend/api/patients/examMedias.js`
- `plugins/patients/frontend/api/patients/examFolders.js`
- `plugins/patients/frontend/routes/patients/Record.vue` (arquivo monolítico ~12k linhas)
- `plugins/patients/frontend/routes/patients/tabs/ExamsTab.vue` (órfão)
- `app/views/api/v1/accounts/patients/exam_medias/*.jbuilder`
- `app/policies/exam_media_policy.rb`
- `db/migrate/20260307200014_create_exam_medias.rb`
- `db/migrate/20260322200003_add_folder_and_lock_to_exam_medias.rb`
- `db/migrate/20260322200005_add_exam_folder_data_to_patients.rb`
- `config/routes.rb:193-198`
- `config/storage.yml`
- `config/environments/development.rb:33-38`
- `config/environments/production.rb:43`
