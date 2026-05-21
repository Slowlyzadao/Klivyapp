files = [
  'docs/01-product/modules/agenda.md', 
  'docs/01-product/modules/financeiro.md', 
  'docs/01-product/modules/pacientes.md', 
  'docs/01-product/modules/configuracoes.md'
]

header = %q{> [!IMPORTANT]
> **Nota de Auditoria Arquitetural Atualizada:** 
> O texto a seguir contém a Especificação Histórica das Regras de Negócio deste módulo.
> Em nível sistêmico (código, frontend, backend e Banco de Dados), todas as estruturas listadas abaixo encontram-se 100% isoladas na Arquitetura Modular (Rails Engines), localizadas especificamente dentro do seu diretório `plugins/`. O modelo de banco de dados original do Chatwoot citado como destino de colunas no documento abaixo já foi refatorado utilizando Satélites DB Profiles (`beclinic_profiles`) visando prevenir colisões de migrações nativas do Chatwoot no longo prazo.
> Leia `02-architecture/system-architecture.md` para visualizar as ligações sistêmicas exatas em código. Tudo detalhado abaixo responde ao Produto e Usuário.

}

files.each do |f|
  if File.exist?(f)
    content = File.read(f)
    unless content.include?('Auditoria Arquitetural Atualizada')
      File.write(f, header + content)
      puts "Prepend aplicado a #{f}"
    end
  else
    puts "Arquivo #{f} não encontrado."
  end
end
