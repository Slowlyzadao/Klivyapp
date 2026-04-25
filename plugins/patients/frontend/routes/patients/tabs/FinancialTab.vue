<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Financeiro do Paciente
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Orçamentos, cobranças, parcelas e pagamentos vinculados ao tratamento.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <button
          class="btn-secondary flex items-center gap-2"
          @click="openEstimateModal()"
        >
          <i class="i-lucide-file-plus w-4 h-4" /> Novo Orçamento
        </button>
        <button
          class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2"
          @click="openPayModal(null)"
        >
          <i class="i-lucide-receipt w-4 h-4" /> Receber Pagamento
        </button>
      </div>
    </div>

    <!-- KPIs financeiros -->
    <div class="fin-kpi-grid mb-5">
      <div class="fin-kpi-card">
        <div class="fin-kpi-icon">
          <i class="i-lucide-trending-up w-3.5 h-3.5" />
        </div>
        <p class="fin-kpi-label">Total Aprovado</p>
        <p class="fin-kpi-value">
          {{ formatCurrency(financialSummary?.total_approved) }}
        </p>
        <p class="fin-kpi-hint">Plano principal</p>
      </div>
      <div class="fin-kpi-card fin-kpi-card--green">
        <div class="fin-kpi-icon fin-kpi-icon--green">
          <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
        </div>
        <p class="fin-kpi-label">Pago / Recebido</p>
        <p class="fin-kpi-value">
          {{ formatCurrency(financialSummary?.total_paid) }}
        </p>
        <p class="fin-kpi-hint">Atualizado</p>
      </div>
      <div class="fin-kpi-card fin-kpi-card--amber">
        <div class="fin-kpi-icon fin-kpi-icon--amber">
          <i class="i-lucide-calendar-clock w-3.5 h-3.5" />
        </div>
        <p class="fin-kpi-label">Em Aberto</p>
        <p class="fin-kpi-value">
          {{ formatCurrency(financialSummary?.total_open) }}
        </p>
        <p class="fin-kpi-hint">
          {{
            financialSummary?.next_due_date
              ? 'Próx: ' + formatDate(financialSummary.next_due_date)
              : 'Sem pendências'
          }}
        </p>
      </div>
      <div class="fin-kpi-card fin-kpi-card--red">
        <div class="fin-kpi-icon fin-kpi-icon--red">
          <i class="i-lucide-alert-circle w-3.5 h-3.5" />
        </div>
        <p class="fin-kpi-label">Devedor (Vencido)</p>
        <p
          class="fin-kpi-value"
          :class="{
            'fin-kpi-value--danger': financialSummary?.total_overdue > 0,
          }"
        >
          {{ formatCurrency(financialSummary?.total_overdue) }}
        </p>
        <p class="fin-kpi-hint">
          {{
            financialSummary?.total_overdue > 0
              ? 'Exige atenção'
              : 'Tudo em dia'
          }}
        </p>
      </div>
      <div class="fin-kpi-card fin-kpi-card--blue">
        <div class="fin-kpi-icon fin-kpi-icon--blue">
          <i class="i-lucide-wallet w-3.5 h-3.5" />
        </div>
        <p class="fin-kpi-label">Crédito</p>
        <p class="fin-kpi-value">
          {{ formatCurrency(financialSummary?.credit_balance) }}
        </p>
        <p class="fin-kpi-hint">Saldo de estornos</p>
      </div>
    </div>

    <!-- Tabs internas + filtros -->
    <div class="fin-tabs-bar mb-4">
      <div class="fin-tabs-list">
        <button
          class="fin-tab"
          :class="
            activeFinancialTab === 'transactions' ? 'fin-tab--active' : ''
          "
          @click="activeFinancialTab = 'transactions'"
        >
          <i class="i-lucide-list w-3.5 h-3.5" /> Transações
        </button>
        <button
          class="fin-tab"
          :class="activeFinancialTab === 'estimates' ? 'fin-tab--active' : ''"
          @click="activeFinancialTab = 'estimates'"
        >
          <i class="i-lucide-file-text w-3.5 h-3.5" /> Orçamentos
          <span v-if="financialEstimates.length" class="fin-tab-badge">{{
            financialEstimates.length
          }}</span>
        </button>
        <button
          class="fin-tab"
          :class="activeFinancialTab === 'receipts' ? 'fin-tab--active' : ''"
          @click="activeFinancialTab = 'receipts'"
        >
          <i class="i-lucide-receipt w-3.5 h-3.5" /> Recibos
        </button>
      </div>
      <div class="flex items-center gap-2">
        <div
          v-if="activeFinancialTab === 'transactions'"
          class="fin-filter-group"
        >
          <button
            v-for="f in [
              { v: 'all', l: 'Todos' },
              { v: 'pendente', l: 'Pendentes' },
              { v: 'pago', l: 'Pagos' },
              { v: 'vencido', l: 'Vencidos' },
            ]"
            :key="f.v"
            class="fin-filter-btn"
            :class="financialFilter === f.v ? 'fin-filter-btn--active' : ''"
            @click="financialFilter = f.v"
          >
            {{ f.l }}
          </button>
        </div>
        <button
          class="fin-icon-btn"
          title="Imprimir Extrato"
          @click="printFinancial()"
        >
          <i class="i-lucide-printer w-4 h-4" />
        </button>
      </div>
    </div>

    <!-- ABA TRANSAÇÕES -->
    <div v-if="activeFinancialTab === 'transactions'">
      <div
        v-if="financialLoading"
        class="flex items-center justify-center py-16"
      >
        <div
          class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
        />
      </div>
      <div v-else class="reg-section">
        <div class="proc-table-wrap">
          <table class="proc-table fin-tx-table">
            <thead>
              <tr class="proc-table-head">
                <th>Vencimento</th>
                <th>Descrição</th>
                <th class="fin-tx-col-parcela">Parcela</th>
                <th class="fin-tx-col-valor">Valor (R$)</th>
                <th class="fin-tx-col-metodo">Método</th>
                <th class="fin-tx-col-status">Status</th>
                <th class="fin-tx-col-acoes">Ações</th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="filteredTransactions.length === 0">
                <td colspan="7" class="proc-table-cell">
                  <div class="proc-empty-state">
                    <div class="proc-empty-icon">
                      <i class="i-lucide-receipt-text w-5 h-5" />
                    </div>
                    <p class="proc-empty-text">Nenhuma transação encontrada.</p>
                  </div>
                </td>
              </tr>
              <tr
                v-for="tx in filteredTransactions"
                :key="tx.id"
                class="proc-table-row"
              >
                <td class="proc-table-cell">
                  <span
                    class="fin-tx-date"
                    :class="{
                      'fin-tx-date--overdue': tx.status === 'vencido',
                      'fin-tx-date--paid': tx.status === 'pago',
                    }"
                  >
                    {{ tx.due_date ? formatDate(tx.due_date) : '—' }}
                  </span>
                </td>
                <td class="proc-table-cell">
                  <p class="proc-cell-primary truncate max-w-[200px]">
                    {{ tx.description || 'Procedimento/Plano' }}
                  </p>
                  <p v-if="tx.paid_at" class="fin-tx-paid-at">
                    Pago em {{ formatDate(tx.paid_at) }}
                  </p>
                </td>
                <td
                  class="proc-table-cell fin-tx-col-parcela proc-cell-secondary"
                >
                  {{ tx.installment_number || '1' }} /
                  {{ tx.total_installments || '1' }}
                </td>
                <td
                  class="proc-table-cell fin-tx-col-valor fin-tx-amount"
                  :class="
                    tx.transaction_type === 'despesa'
                      ? 'fin-tx-amount--expense'
                      : 'fin-tx-amount--income'
                  "
                >
                  {{ formatCurrency(tx.amount) }}
                </td>
                <td class="proc-table-cell fin-tx-col-metodo">
                  <span v-if="tx.payment_method" class="fin-method-badge">
                    {{
                      {
                        pix: 'PIX',
                        cartao_credito: 'Crédito',
                        cartao_debito: 'Débito',
                        dinheiro: 'Dinheiro',
                        boleto: 'Boleto',
                        transferencia: 'Transf.',
                        outros: 'Outros',
                      }[tx.payment_method] || tx.payment_method
                    }}
                  </span>
                  <span v-else class="proc-cell-secondary">—</span>
                </td>
                <td class="proc-table-cell fin-tx-col-status">
                  <span
                    class="docs-status-badge"
                    :class="txStatusConfig(tx.status).cls"
                  >
                    <i
                      :class="txStatusConfig(tx.status).icon"
                      class="w-3 h-3 mr-1"
                    />
                    {{ txStatusConfig(tx.status).label }}
                  </span>
                </td>
                <td class="proc-table-cell text-right">
                  <div class="fin-tx-actions">
                    <button
                      v-if="tx.status === 'pendente' || tx.status === 'vencido'"
                      class="fin-action-btn fin-action-btn--green"
                      @click="openPayModal(tx.id)"
                    >
                      <i class="i-lucide-check w-3 h-3" /> Receber
                    </button>
                    <button
                      v-if="tx.status === 'pendente' || tx.status === 'vencido'"
                      class="fin-icon-btn"
                      title="Cobrar via WhatsApp"
                      @click="chargeWhatsapp(tx.id)"
                    >
                      <i class="i-lucide-message-circle w-4 h-4" />
                    </button>
                    <button
                      v-if="tx.status === 'pago' && tx.payment_proof_url"
                      class="fin-icon-btn"
                      title="Ver comprovante"
                      @click="viewProof(tx)"
                    >
                      <i class="i-lucide-file-text w-4 h-4" />
                    </button>
                    <button
                      v-if="tx.status === 'pago' && !tx.payment_proof_url"
                      class="fin-icon-btn"
                      title="Anexar comprovante"
                      @click="openProofModal(tx.id)"
                    >
                      <i class="i-lucide-upload w-4 h-4" />
                    </button>
                    <button
                      v-if="tx.status === 'pago'"
                      class="fin-icon-btn"
                      title="Estornar transação"
                      @click="refundTransaction(tx.id)"
                    >
                      <i class="i-lucide-undo w-4 h-4" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- ABA ORÇAMENTOS -->
    <div v-else-if="activeFinancialTab === 'estimates'">
      <div
        v-if="financialLoading"
        class="flex items-center justify-center py-16"
      >
        <div
          class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
        />
      </div>
      <div v-else class="flex flex-col gap-4">
        <div v-if="financialEstimates.length === 0" class="reg-section">
          <div class="proc-empty-state">
            <div class="proc-empty-icon">
              <i class="i-lucide-file-text w-5 h-5" />
            </div>
            <p class="proc-empty-text">Nenhum orçamento encontrado.</p>
            <p class="proc-empty-hint">
              Clique em "Novo Orçamento" para criar.
            </p>
          </div>
        </div>
        <div
          v-for="est in financialEstimates"
          :key="est.id"
          class="fin-estimate-card"
        >
          <div class="fin-estimate-body">
            <div class="fin-estimate-meta">
              <span
                class="docs-status-badge"
                :class="estimateStatusConfig(est.status).cls"
              >
                {{ estimateStatusConfig(est.status).label }}
              </span>
              <span class="fin-estimate-id">Orçamento #{{ est.id }}</span>
              <span v-if="est.treatment_plan_id" class="fin-plan-badge">
                <i class="i-lucide-link w-3 h-3" /> Plano de Tratamento
              </span>
            </div>

            <div class="fin-estimate-values">
              <div class="fin-estimate-value-item">
                <p class="fin-estimate-value-label">Subtotal</p>
                <p class="fin-estimate-value-amount">
                  {{ formatCurrency(est.subtotal) }}
                </p>
              </div>
              <div class="fin-estimate-value-item">
                <p class="fin-estimate-value-label">Desconto</p>
                <p
                  class="fin-estimate-value-amount fin-estimate-value-amount--red"
                >
                  - {{ formatCurrency(est.discount_amount) }}
                </p>
              </div>
              <div class="fin-estimate-value-item">
                <p class="fin-estimate-value-label">Total</p>
                <p
                  class="fin-estimate-value-amount fin-estimate-value-amount--green fin-estimate-value-amount--lg"
                >
                  {{ formatCurrency(est.total) }}
                </p>
              </div>
              <div class="fin-estimate-value-item">
                <p class="fin-estimate-value-label">Parcelas</p>
                <p class="fin-estimate-value-amount">
                  {{ est.installments_count }}x de
                  {{ formatCurrency(est.installment_value) }}
                </p>
              </div>
            </div>

            <div class="fin-estimate-summary">
              <div class="fin-estimate-value-item">
                <p class="fin-estimate-value-label">Pago</p>
                <p
                  class="fin-estimate-value-amount fin-estimate-value-amount--green"
                >
                  {{ formatCurrency(est.financial_summary?.total_paid) }}
                </p>
              </div>
              <div class="fin-estimate-value-item">
                <p class="fin-estimate-value-label">Pendente</p>
                <p
                  class="fin-estimate-value-amount fin-estimate-value-amount--amber"
                >
                  {{ formatCurrency(est.financial_summary?.total_pending) }}
                </p>
              </div>
              <div class="fin-estimate-value-item">
                <p class="fin-estimate-value-label">Vencido</p>
                <p
                  class="fin-estimate-value-amount fin-estimate-value-amount--red"
                >
                  {{ formatCurrency(est.financial_summary?.total_overdue) }}
                </p>
              </div>
            </div>

            <div v-if="est.notes" class="fin-estimate-notes">
              {{ est.notes }}
            </div>
          </div>

          <div class="fin-estimate-actions">
            <div class="fin-estimate-dates">
              <p>Criado em {{ formatDate(est.created_at) }}</p>
              <p v-if="est.valid_until" class="fin-estimate-valid">
                Válido até {{ formatDate(est.valid_until) }}
              </p>
            </div>
            <div class="flex gap-2">
              <button
                v-if="est.status === 'rascunho' || est.status === 'enviado'"
                class="fin-action-btn fin-action-btn--green"
                @click="approveEstimate(est.id)"
              >
                <i class="i-lucide-check-circle w-3.5 h-3.5" /> Aprovar
              </button>
              <button
                v-if="est.status !== 'cancelado' && est.status !== 'aprovado'"
                class="fin-action-btn fin-action-btn--danger"
                @click="cancelEstimate(est.id)"
              >
                <i class="i-lucide-x-circle w-3.5 h-3.5" /> Cancelar
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ABA RECIBOS -->
    <div v-else-if="activeFinancialTab === 'receipts'">
      <div class="reg-section">
        <div class="proc-table-wrap">
          <table class="proc-table">
            <thead>
              <tr class="proc-table-head">
                <th>Data Pagamento</th>
                <th>Descrição</th>
                <th>Valor (R$)</th>
                <th>Método</th>
                <th class="text-right">Recibo</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-if="
                  transactions.filter(t => t.status === 'pago').length === 0
                "
              >
                <td colspan="5" class="proc-table-cell">
                  <div class="proc-empty-state">
                    <div class="proc-empty-icon">
                      <i class="i-lucide-file-check w-5 h-5" />
                    </div>
                    <p class="proc-empty-text">
                      Nenhum pagamento confirmado ainda.
                    </p>
                  </div>
                </td>
              </tr>
              <tr
                v-for="tx in transactions.filter(t => t.status === 'pago')"
                :key="'r-' + tx.id"
                class="proc-table-row fin-tx-row--paid"
              >
                <td class="proc-table-cell proc-cell-secondary font-mono">
                  {{
                    tx.paid_at
                      ? formatDate(tx.paid_at)
                      : formatDate(tx.updated_at)
                  }}
                </td>
                <td class="proc-table-cell proc-cell-primary">
                  {{ tx.description || 'Pagamento' }}
                </td>
                <td class="proc-table-cell fin-tx-amount fin-tx-amount--income">
                  {{ formatCurrency(tx.amount) }}
                </td>
                <td class="proc-table-cell">
                  <span class="fin-method-badge">
                    {{
                      {
                        pix: 'PIX',
                        cartao_credito: 'Crédito',
                        cartao_debito: 'Débito',
                        dinheiro: 'Dinheiro',
                        boleto: 'Boleto',
                        transferencia: 'Transf.',
                        outros: 'Outros',
                      }[tx.payment_method] || '—'
                    }}
                  </span>
                </td>
                <td class="proc-table-cell text-right">
                  <button
                    class="fin-action-btn fin-action-btn--green"
                    @click="printReceipt(tx)"
                  >
                    <i class="i-lucide-receipt w-3.5 h-3.5" /> Recibo
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- MODAL: Preview de Impressão -->
    <div
      v-if="showPrintModal"
      class="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm"
      @click.self="showPrintModal = false"
    >
      <div
        class="bg-slate-900 border border-slate-700 rounded-xl shadow-2xl w-full max-w-4xl h-[90vh] flex flex-col overflow-hidden relative"
      >
        <div
          class="flex items-center justify-between px-4 py-3 border-b border-slate-700/50 flex-shrink-0"
        >
          <h3
            class="text-base font-semibold text-slate-100 flex items-center gap-2"
          >
            <i class="i-lucide-printer text-sky-400" /> {{ printTitle }}
          </h3>
          <div class="flex items-center gap-3">
            <button
              class="h-8 px-3 rounded-lg bg-white text-slate-900 font-semibold text-xs hover:bg-slate-100 flex items-center gap-2 transition-colors"
              @click="$refs.previewIframe.contentWindow.print()"
            >
              <i class="i-lucide-printer" /> Imprimir / PDF
            </button>
            <button
              class="p-1 rounded-lg hover:bg-slate-800 text-slate-400 transition-colors"
              @click="showPrintModal = false"
            >
              <i class="i-lucide-x" />
            </button>
          </div>
        </div>
        <div class="flex-1 bg-slate-800 overflow-hidden relative">
          <iframe
            ref="previewIframe"
            :srcdoc="printHtmlContent"
            class="w-full h-full border-none bg-white block absolute inset-0"
            title="Visualização de Impressão"
          />
        </div>
      </div>
    </div>

    <!-- MODAL: Anexar Comprovante -->
    <div
      v-if="showProofModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      @click.self="showProofModal = false"
    >
      <div
        class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
      >
        <div
          class="flex items-center justify-between p-6 border-b border-slate-700/50"
        >
          <div>
            <h3
              class="text-lg font-semibold text-slate-100 flex items-center gap-2"
            >
              <i class="i-lucide-paperclip text-sky-400" /> Anexar Comprovante
            </h3>
            <p class="text-xs text-slate-400 mt-0.5">
              Anexe o comprovante de pagamento (PIX, boleto, etc.)
            </p>
          </div>
          <button
            class="p-2 rounded-lg hover:bg-slate-800 text-slate-400"
            @click="showProofModal = false"
          >
            <i class="i-lucide-x" />
          </button>
        </div>
        <div class="p-6 space-y-4">
          <div v-if="proofTx" class="bg-slate-800 rounded-xl p-4 space-y-1">
            <p class="text-xs text-slate-400">Transação</p>
            <p class="text-sm font-semibold text-slate-200">
              {{ proofTx.description || 'Pagamento' }}
            </p>
            <p class="text-lg font-bold text-emerald-400">
              {{ formatCurrency(proofTx.amount) }}
            </p>
          </div>
          <label class="block">
            <span class="text-sm text-slate-300 mb-2 block"
              >Arquivo (imagem ou PDF)</span
            >
            <div
              class="border-2 border-dashed border-slate-600 hover:border-sky-500 rounded-xl p-8 text-center cursor-pointer transition-colors relative"
            >
              <i
                class="i-lucide-upload-cloud text-3xl text-slate-500 block mb-2"
              />
              <p class="text-sm text-slate-400">
                Clique para selecionar ou arraste o arquivo
              </p>
              <p class="text-xs text-slate-600 mt-1">
                PNG, JPG, PDF — máx. 10MB
              </p>
              <input
                type="file"
                accept="image/*,application/pdf"
                class="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
                :disabled="proofUploading"
                @change="handleProofUpload"
              />
            </div>
          </label>
          <div
            v-if="proofUploading"
            class="flex items-center gap-2 text-sky-400 text-sm"
          >
            <i class="i-lucide-loader-2 animate-spin" /> Enviando comprovante...
          </div>
        </div>
      </div>
    </div>

    <!-- MODAL: Receber Pagamento -->

    <div
      v-if="showPayModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      @click.self="showPayModal = false"
    >
      <div
        class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
      >
        <div
          class="flex items-center justify-between p-6 border-b border-slate-700/50"
        >
          <div>
            <h3
              class="text-lg font-semibold text-slate-100 flex items-center gap-2"
            >
              <i class="i-lucide-receipt text-emerald-400" /> Registrar
              Pagamento
            </h3>
            <p class="text-xs text-slate-400 mt-0.5">
              Confirme o método e data do pagamento
            </p>
          </div>
          <button
            class="text-slate-400 hover:text-slate-100"
            @click="showPayModal = false"
          >
            <i class="i-lucide-x text-xl" />
          </button>
        </div>
        <div class="p-6 space-y-4">
          <!-- Seletor de parcela (quando aberto pelo botão do header) -->
          <div v-if="selectedTxId === null">
            <label class="block text-sm font-medium text-slate-300 mb-2"
              >Selecionar Parcela *</label
            >
            <div
              v-if="pendingTransactions.length === 0"
              class="bg-slate-800/50 border border-slate-700 rounded-xl p-4 text-center text-slate-500 text-sm"
            >
              <i
                class="i-lucide-check-circle-2 text-2xl mb-1 block text-emerald-400"
              />
              Nenhuma parcela pendente. Todas as parcelas estão pagas!
            </div>
            <div v-else class="space-y-2 max-h-48 overflow-y-auto">
              <button
                v-for="pt in pendingTransactions"
                :key="pt.id"
                class="w-full flex items-center justify-between p-3 rounded-xl border text-left transition-all"
                :class="
                  selectedTxId === pt.id
                    ? 'bg-emerald-500/15 border-emerald-500/50'
                    : 'bg-slate-800/50 border-slate-700 hover:border-slate-600'
                "
                @click="selectedTxId = pt.id"
              >
                <div>
                  <p
                    class="text-sm font-medium text-slate-200 truncate max-w-[200px]"
                  >
                    {{ pt.description || 'Parcela' }}
                  </p>
                  <p class="text-xs text-slate-500 mt-0.5">
                    Venc:
                    {{ pt.due_date ? formatDate(pt.due_date) : '—' }} · Parcela
                    {{ pt.installment_number }}/{{ pt.total_installments }}
                  </p>
                </div>
                <div class="text-right shrink-0 ml-4">
                  <p class="font-mono font-semibold text-emerald-400">
                    {{ formatCurrency(pt.amount) }}
                  </p>
                  <span
                    class="text-[10px] font-medium px-1.5 py-0.5 rounded-full border"
                    :class="txStatusConfig(pt.status).cls"
                  >
                    {{ txStatusConfig(pt.status).label }}
                  </span>
                </div>
              </button>
            </div>
          </div>
          <!-- Info da parcela já selecionada -->
          <div
            v-else
            class="bg-emerald-500/10 border border-emerald-500/20 rounded-xl p-3 flex items-center justify-between"
          >
            <div>
              <p class="text-xs text-emerald-400 font-medium">
                Parcela selecionada
              </p>
              <p class="text-sm text-slate-200 mt-0.5">
                {{
                  transactions.find(t => t.id === selectedTxId)?.description ||
                  'Parcela'
                }}
              </p>
            </div>
            <button
              class="text-slate-400 hover:text-red-400 text-xs"
              @click="selectedTxId = null"
            >
              Trocar
            </button>
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Método de Pagamento *</label
            >
            <div class="grid grid-cols-3 gap-2">
              <button
                v-for="m in [
                  { v: 'pix', l: 'PIX', icon: 'i-lucide-qr-code' },
                  {
                    v: 'dinheiro',
                    l: 'Dinheiro',
                    icon: 'i-lucide-banknote',
                  },
                  {
                    v: 'cartao_credito',
                    l: 'Crédito',
                    icon: 'i-lucide-credit-card',
                  },
                  {
                    v: 'cartao_debito',
                    l: 'Débito',
                    icon: 'i-lucide-credit-card',
                  },
                  {
                    v: 'transferencia',
                    l: 'Transf.',
                    icon: 'i-lucide-arrow-right-left',
                  },
                  {
                    v: 'boleto',
                    l: 'Boleto',
                    icon: 'i-lucide-file-text',
                  },
                ]"
                :key="m.v"
                class="flex flex-col items-center gap-1 p-2.5 rounded-xl border text-xs font-medium transition-all"
                :class="
                  payForm.payment_method === m.v
                    ? 'bg-emerald-500/15 border-emerald-500/50 text-emerald-400'
                    : 'bg-slate-800/50 border-slate-700 text-slate-400 hover:border-slate-600 hover:text-slate-200'
                "
                @click="payForm.payment_method = m.v"
              >
                <i :class="m.icon" />
                {{ m.l }}
              </button>
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Data do Pagamento</label
            >
            <input
              v-model="payForm.paid_at"
              type="date"
              class="form-input w-full"
            />
          </div>
        </div>
        <div class="p-6 border-t border-slate-700/50 flex justify-end gap-3">
          <button class="btn-secondary" @click="showPayModal = false">
            Cancelar
          </button>
          <button
            class="btn-primary bg-emerald-600 hover:bg-emerald-500 text-white flex items-center gap-2 disabled:opacity-50"
            :disabled="payModalLoading || !selectedTxId"
            @click="confirmPayment()"
          >
            <i v-if="payModalLoading" class="i-lucide-loader-2 animate-spin" />
            <i v-else class="i-lucide-check" />
            Confirmar Pagamento
          </button>
        </div>
      </div>
    </div>

    <!-- MODAL: Novo Orçamento -->
    <div
      v-if="showEstimateModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      @click.self="showEstimateModal = false"
    >
      <div
        class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-lg"
      >
        <div
          class="flex items-center justify-between p-6 border-b border-slate-700/50"
        >
          <div>
            <h3
              class="text-lg font-semibold text-slate-100 flex items-center gap-2"
            >
              <i class="i-lucide-file-plus text-blue-400" /> Novo Orçamento
            </h3>
            <p class="text-xs text-slate-400 mt-0.5">
              Crie um orçamento avulso para este paciente
            </p>
          </div>
          <button
            class="text-slate-400 hover:text-slate-100"
            @click="showEstimateModal = false"
          >
            <i class="i-lucide-x text-xl" />
          </button>
        </div>
        <div class="p-6 space-y-4">
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1.5">Subtotal (R$) *</label
              >
              <div class="relative">
                <span
                  class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 text-sm font-medium z-10 pointer-events-none"
                  >R$</span
                >
                <input
                  :value="subtotalRaw"
                  type="text"
                  inputmode="numeric"
                  placeholder="0,00"
                  style="padding-left: 2.25rem !important"
                  class="form-input w-full font-mono"
                  @input="onSubtotalInput"
                />
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1.5">Parcelas</label
              >
              <input
                v-model="estimateForm.installments_count"
                type="number"
                min="1"
                max="60"
                class="form-input w-full"
              />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1.5">Tipo de Desconto</label
              >
              <select
                v-model="estimateForm.discount_type"
                class="form-input w-full"
              >
                <option value="fixo">Valor Fixo (R$)</option>
                <option value="percentual">Percentual (%)</option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1.5">Valor Desconto</label
              >
              <input
                v-model="estimateForm.discount_value"
                type="number"
                step="0.01"
                min="0"
                class="form-input w-full"
              />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1.5">Método Padrão</label
              >
              <select
                v-model="estimateForm.payment_method"
                class="form-input w-full"
              >
                <option value="pix">PIX</option>
                <option value="cartao_credito">Cartão de Crédito</option>
                <option value="cartao_debito">Cartão de Débito</option>
                <option value="dinheiro">Dinheiro</option>
                <option value="boleto">Boleto</option>
                <option value="transferencia">Transferência</option>
                <option value="outros">Outros</option>
              </select>
            </div>
            <div>
              <label class="block text-sm font-medium text-slate-300 mb-1.5">1º Vencimento</label
              >
              <input
                v-model="estimateForm.valid_until"
                type="date"
                class="form-input w-full"
              />
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">Observações</label
            >
            <textarea
              v-model="estimateForm.notes"
              rows="2"
              placeholder="Observações sobre o orçamento..."
              class="form-input w-full resize-none"
            />
          </div>
          <!-- Preview do total -->
          <div
            v-if="subtotalRaw"
            class="bg-slate-800/50 border border-slate-700/50 rounded-xl p-3 flex items-center justify-between"
          >
            <div class="text-xs text-slate-400">
              <span
                >Subtotal:
                <strong class="text-slate-200"
                  >R$ {{ subtotalRaw }}</strong
                ></span
              >
              <span
                v-if="estimateForm.discount_value > 0"
                class="ml-3 text-red-400"
              >
                - Desconto:
                {{
                  estimateForm.discount_type === 'percentual'
                    ? estimateForm.discount_value + '%'
                    : 'R$ ' + estimateForm.discount_value
                }}
              </span>
            </div>
            <div class="text-right">
              <p class="text-xs text-slate-400">
                {{ estimateForm.installments_count }}x de
              </p>
              <p class="text-sm font-bold text-emerald-400 font-mono">
                {{
                  formatCurrency(
                    parseCurrencyInput(subtotalRaw) /
                      (parseInt(estimateForm.installments_count) || 1)
                  )
                }}
              </p>
            </div>
          </div>
        </div>
        <div class="p-6 border-t border-slate-700/50 flex justify-end gap-3">
          <button class="btn-secondary" @click="showEstimateModal = false">
            Cancelar
          </button>
          <button
            class="btn-primary bg-blue-600 hover:bg-blue-500 text-white flex items-center gap-2 disabled:opacity-50"
            :disabled="estimateModalLoading || !subtotalRaw"
            @click="confirmCreateEstimate()"
          >
            <i
              v-if="estimateModalLoading"
              class="i-lucide-loader-2 animate-spin"
            />
            <i v-else class="i-lucide-file-check" />
            Criar Orçamento
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
