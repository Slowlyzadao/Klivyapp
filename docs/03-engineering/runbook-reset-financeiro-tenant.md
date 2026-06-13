# Runbook — Zerar lançamentos financeiros de uma clínica (account)

> Resetar os **lançamentos** financeiros de **uma** conta (tenant) em produção, mantendo a **config** (contas bancárias, plano de contas, formas de pagamento, comissões etc.). Executado pela 1ª vez na **account 21** em 2026-06-02 (soft delete).

## ⚠️ Antes de tudo

- **Produção + multi-tenant.** Tudo é scoped por `account_id`. Os scripts **exigem `ACCOUNT_ID`** (via env) e **não têm default** — se esquecer, falham com erro em vez de apagar a conta errada.
- Há uma **guarda interna**: dentro da transação, se a contagem de `entries` de **outras** contas mudar, o script dá `raise` e faz **rollback de tudo**. Impossível vazar pra outro tenant.
- **NUNCA cole o Ruby direto no shell** (vira `command not found`). Use o one-liner base64 → grava o arquivo → roda via `rails runner ARQUIVO`.
- **Sempre rode o DRY-RUN primeiro** (não altera nada) e confira a tabela `ACC` vs `OUTRAS` + o "Saldo ANTES". Só então rode com `CONFIRM=yes`.
- Onde rodar: console do serviço no EasyPanel (container Klivy, `/app`).

## Soft delete vs Hard delete

| | **Soft delete** (recomendado) | **Hard delete** |
|---|---|---|
| O que faz | seta `deleted_at` (oculta) | remove a linha do banco |
| Reversível? | **Sim** (restore) | **NÃO — permanente** |
| Efeito na UI | Fluxo/A Receber/A Pagar/DRE/aba paciente zeram | idem |
| `payment_receipt_items` / `budget_items` | ficam ocultos com o pai (não têm `deleted_at`) | **removidos** |
| Quando usar | reset de teste, padrão | purga física (cliente teste → produção real) |

**O que é MANTIDO** (config, em ambos): `bank_accounts`, `dre_categories`, `payment_methods`, `payment_method_fees`, `commission_rules`, `service_pricings`, `agent_profiles`, `revenue_goals`, `gateway_settings`, `setup_states`.

**O que é APAGADO** (movimento): `entries`, `payment_receipts`, `payment_receipt_items`, `installments`, `expenses`, `budgets`, `budget_items`, `cash_movements`, `cash_registers`, `commission_entries`, `refunds`, `patient_credits`, `recurring_billings`, `recurring_expenses`.

> Os Planos de Tratamento (clínicos) **não** são tocados — só o orçamento financeiro gerado deles.

---

## A) SOFT DELETE (padrão)

**1. Gravar o script** (uma linha, paste-safe):

```bash
echo 'YWlkID0gSW50ZWdlcihFTlYuZmV0Y2goIkFDQ09VTlRfSUQiKSkgICAjIG9icmlnYXRvcmlvOyBzZW0gZGVmYXVsdCBwcmEgbnVuY2EgYXBhZ2FyIGEgY29udGEgZXJyYWRhCmNvbmZpcm0gPSBFTlZbIkNPTkZJUk0iXSA9PSAieWVzIgpBY3RpdmVSZWNvcmQ6OkJhc2UubG9nZ2VyID0gbmlsCgptb3ZlbWVudCA9IHsKICAiZW50cmllcyI9PkZpbmFuY2lhbDo6RW50cnksICJwYXltZW50X3JlY2VpcHRzIj0+RmluYW5jaWFsOjpQYXltZW50UmVjZWlwdCwKICAicGF5bWVudF9yZWNlaXB0X2l0ZW1zIj0+RmluYW5jaWFsOjpQYXltZW50UmVjZWlwdEl0ZW0sICJpbnN0YWxsbWVudHMiPT5GaW5hbmNpYWw6Okluc3RhbGxtZW50LAogICJleHBlbnNlcyI9PkZpbmFuY2lhbDo6RXhwZW5zZSwgImJ1ZGdldHMiPT5GaW5hbmNpYWw6OkJ1ZGdldCwgImJ1ZGdldF9pdGVtcyI9PkZpbmFuY2lhbDo6QnVkZ2V0SXRlbSwKICAiY2FzaF9tb3ZlbWVudHMiPT5GaW5hbmNpYWw6OkNhc2hNb3ZlbWVudCwgImNhc2hfcmVnaXN0ZXJzIj0+RmluYW5jaWFsOjpDYXNoUmVnaXN0ZXIsCiAgImNvbW1pc3Npb25fZW50cmllcyI9PkZpbmFuY2lhbDo6Q29tbWlzc2lvbkVudHJ5LCAicmVmdW5kcyI9PkZpbmFuY2lhbDo6UmVmdW5kLAogICJwYXRpZW50X2NyZWRpdHMiPT5GaW5hbmNpYWw6OlBhdGllbnRDcmVkaXQsICJyZWN1cnJpbmdfYmlsbGluZ3MiPT5GaW5hbmNpYWw6OlJlY3VycmluZ0JpbGxpbmcsCiAgInJlY3VycmluZ19leHBlbnNlcyI9PkZpbmFuY2lhbDo6UmVjdXJyaW5nRXhwZW5zZQp9CgpzYWxkbyA9IGxhbWJkYSBkbwogIEZpbmFuY2lhbDo6QmFua0FjY291bnQudW5zY29wZWQud2hlcmUoYWNjb3VudF9pZDogYWlkLCBkZWxldGVkX2F0OiBuaWwpLm9yZGVyKDppZCkubWFwIGRvIHxifAogICAgcmVsID0gRmluYW5jaWFsOjpFbnRyeS51bnNjb3BlZC53aGVyZShhY2NvdW50X2lkOiBhaWQsIGZpbmFuY2lhbF9iYW5rX2FjY291bnRfaWQ6IGIuaWQsIGFmZmVjdHNfY2FzaGZsb3c6IHRydWUsIGRlbGV0ZWRfYXQ6IG5pbCkud2hlcmUoImNhc2hfZGF0ZSA8PSA/IiwgRGF0ZS5jdXJyZW50KQogICAgZXN0ID0gYi5pbml0aWFsX2JhbGFuY2VfY2VudHMgKyByZWwud2hlcmUoZGlyZWN0aW9uOiAiaW4iKS5zdW0oOmFtb3VudF9jZW50cykgLSByZWwud2hlcmUoZGlyZWN0aW9uOiAib3V0Iikuc3VtKDphbW91bnRfY2VudHMpCiAgICBbYi5pZCwgYi5uYW1lLCBlc3RdCiAgZW5kCmVuZAoKb3RoZXJzX2JlZm9yZSA9IEZpbmFuY2lhbDo6RW50cnkudW5zY29wZWQud2hlcmUubm90KGFjY291bnRfaWQ6IGFpZCkud2hlcmUoZGVsZXRlZF9hdDogbmlsKS5jb3VudApwdXRzICI9PT0gU09GVCBERUxFVEUgbGFuY2FtZW50b3MgYWNjb3VudCAje2FpZH0gLSBtb2RvOiAje2NvbmZpcm0gPyAnRVhFQ1VDQU8nIDogJ0RSWS1SVU4nfSA9PT0iCnB1dHMgZm9ybWF0KCIgICUtMjJzICUtOHMgJS04cyAlLTEycyIsICJ0YWJlbGEiLCAiQUNDIiwgIk9VVFJBUyIsICJhY2FvIikKcGxhbiA9IHt9Cm1vdmVtZW50LmVhY2ggZG8gfGxhYmVsLCBrfAogIHNkID0gay5jb2x1bW5fbmFtZXMuaW5jbHVkZT8oImRlbGV0ZWRfYXQiKQogIGEgPSBzZCA/IGsudW5zY29wZWQud2hlcmUoYWNjb3VudF9pZDogYWlkLCBkZWxldGVkX2F0OiBuaWwpLmNvdW50IDogay51bnNjb3BlZC53aGVyZShhY2NvdW50X2lkOiBhaWQpLmNvdW50CiAgbyA9IHNkID8gay51bnNjb3BlZC53aGVyZS5ub3QoYWNjb3VudF9pZDogYWlkKS53aGVyZShkZWxldGVkX2F0OiBuaWwpLmNvdW50IDogay51bnNjb3BlZC53aGVyZS5ub3QoYWNjb3VudF9pZDogYWlkKS5jb3VudAogIHBsYW5bbGFiZWxdID0gW2ssIHNkXQogIHB1dHMgZm9ybWF0KCIgICUtMjJzICUtOGQgJS04ZCAlLTEycyIsIGxhYmVsLCBhLCBvLCBzZCA/ICJzb2Z0LWRlbGV0ZSIgOiAic2tpcChzZW0gc2QpIikKZW5kCnB1dHMgIiIKcHV0cyAiU2FsZG8gZXN0aW1hZG8gQU5URVM6IgpzYWxkby5jYWxsLmVhY2ggeyB8aWQsIG4sIGV8IHB1dHMgZm9ybWF0KCIgICMlLTNkICUtMThzIFIkICUuMmYiLCBpZCwgbiwgZSAvIDEwMC4wKSB9CnVubGVzcyBjb25maXJtCiAgcHV0cyAiIgogIHB1dHMgIj4+IERSWS1SVU46IG5hZGEgYWx0ZXJhZG8uIFJvZGUgZGUgbm92byBjb20gQ09ORklSTT15ZXMgcGFyYSBzb2Z0LWRlbGV0YXIuIgogIGV4aXQgMAplbmQKcmVzID0ge307IG5vdyA9IFRpbWUuY3VycmVudApBY3RpdmVSZWNvcmQ6OkJhc2UudHJhbnNhY3Rpb24gZG8KICBwbGFuLmVhY2ggeyB8bGFiZWwsIChrLCBzZCl8IG5leHQgdW5sZXNzIHNkOyByZXNbbGFiZWxdID0gay51bnNjb3BlZC53aGVyZShhY2NvdW50X2lkOiBhaWQsIGRlbGV0ZWRfYXQ6IG5pbCkudXBkYXRlX2FsbChkZWxldGVkX2F0OiBub3csIHVwZGF0ZWRfYXQ6IG5vdykgfQogIG9hID0gRmluYW5jaWFsOjpFbnRyeS51bnNjb3BlZC53aGVyZS5ub3QoYWNjb3VudF9pZDogYWlkKS53aGVyZShkZWxldGVkX2F0OiBuaWwpLmNvdW50CiAgcmFpc2UgIkFCT1JUOiBPVVRSQVMgY29udGFzIG11ZGFyYW0gKCN7b3RoZXJzX2JlZm9yZX0gLT4gI3tvYX0pISIgaWYgb2EgIT0gb3RoZXJzX2JlZm9yZQplbmQKcHV0cyAiIgpwdXRzICI9PT0gU09GVC1ERUxFVEFETyA9PT0iOyByZXMuZWFjaCB7IHxraywgdnwgcHV0cyBmb3JtYXQoIiAgJS0yMnMgJWQiLCBraywgdikgfQpwdXRzICIiCnB1dHMgIlNhbGRvIGVzdGltYWRvIERFUE9JUyAoZXNwZXJhZG8gUiQgMCwwMCk6IgpzYWxkby5jYWxsLmVhY2ggeyB8aWQsIG4sIGV8IHB1dHMgZm9ybWF0KCIgICMlLTNkICUtMThzIFIkICUuMmYiLCBpZCwgbiwgZSAvIDEwMC4wKSB9CnB1dHMgIiIKcHV0cyAiT1VUUkFTIGVudHJpZXMgaW50YWN0YXM6ICN7RmluYW5jaWFsOjpFbnRyeS51bnNjb3BlZC53aGVyZS5ub3QoYWNjb3VudF9pZDogYWlkKS53aGVyZShkZWxldGVkX2F0OiBuaWwpLmNvdW50fSAoZXJhICN7b3RoZXJzX2JlZm9yZX0pIgpwdXRzICJPSy4gRGVzZmF6ZXI6IEFDQ09VTlRfSUQ9I3thaWR9IC4uLiByZXN0b3JlICh2ZXIgcnVuYm9vaykuIgo=' | base64 -d > /app/fin_soft_reset.rb
```

**2. DRY-RUN** (troque `21` pela conta alvo):

```bash
ACCOUNT_ID=21 RAILS_ENV=production bundle exec rails runner /app/fin_soft_reset.rb
```

**3. Executar** (depois de conferir o dry-run):

```bash
ACCOUNT_ID=21 CONFIRM=yes RAILS_ENV=production bundle exec rails runner /app/fin_soft_reset.rb
```

Esperado: `Saldo DEPOIS = R$ 0,00`, `OUTRAS entries intactas: N (era N)`.

### Desfazer o soft delete (restore)

Grava o restore (anote a hora em que rodou o soft delete — só restaura o que foi deletado **a partir** dela, via `SINCE`):

```bash
echo 'YWlkID0gSW50ZWdlcihFTlYuZmV0Y2goIkFDQ09VTlRfSUQiKSkKc2luY2UgPSBUaW1lLnBhcnNlKEVOVi5mZXRjaCgiU0lOQ0UiKSkgICAjIGV4OiAiMjAyNi0wNi0wMiAxNTo0NCIgLSBzbyByZXN0YXVyYSBvIHF1ZSBmb2kgZGVsZXRhZG8gZGVwb2lzIGRpc3NvCmNvbmZpcm0gPSBFTlZbIkNPTkZJUk0iXSA9PSAieWVzIgpBY3RpdmVSZWNvcmQ6OkJhc2UubG9nZ2VyID0gbmlsCm1vZGVscyA9IFtGaW5hbmNpYWw6OkVudHJ5LCBGaW5hbmNpYWw6OlBheW1lbnRSZWNlaXB0LCBGaW5hbmNpYWw6Okluc3RhbGxtZW50LCBGaW5hbmNpYWw6OkV4cGVuc2UsCiAgICAgICAgICBGaW5hbmNpYWw6OkJ1ZGdldCwgRmluYW5jaWFsOjpDYXNoTW92ZW1lbnQsIEZpbmFuY2lhbDo6Q2FzaFJlZ2lzdGVyLCBGaW5hbmNpYWw6OkNvbW1pc3Npb25FbnRyeSwKICAgICAgICAgIEZpbmFuY2lhbDo6UmVmdW5kLCBGaW5hbmNpYWw6OlBhdGllbnRDcmVkaXQsIEZpbmFuY2lhbDo6UmVjdXJyaW5nQmlsbGluZywgRmluYW5jaWFsOjpSZWN1cnJpbmdFeHBlbnNlXQpwdXRzICI9PT0gUkVTVE9SRSBzb2Z0LWRlbGV0ZSBhY2NvdW50ICN7YWlkfSBkZXNkZSAje3NpbmNlfSAtIG1vZG86ICN7Y29uZmlybSA/ICdFWEVDVUNBTycgOiAnRFJZLVJVTid9ID09PSIKbW9kZWxzLmVhY2ggZG8gfGt8CiAgbmV4dCB1bmxlc3Mgay5jb2x1bW5fbmFtZXMuaW5jbHVkZT8oImRlbGV0ZWRfYXQiKQogIHJlbCA9IGsudW5zY29wZWQud2hlcmUoYWNjb3VudF9pZDogYWlkKS53aGVyZSgiZGVsZXRlZF9hdCA+PSA/Iiwgc2luY2UpCiAgcHV0cyBmb3JtYXQoIiAgJS0yNnMgJWQiLCBrLm5hbWUsIHJlbC5jb3VudCkKICByZWwudXBkYXRlX2FsbChkZWxldGVkX2F0OiBuaWwsIGRlbGV0ZWRfYnlfaWQ6IG5pbCwgdXBkYXRlZF9hdDogVGltZS5jdXJyZW50KSBpZiBjb25maXJtCmVuZApwdXRzIGNvbmZpcm0gPyAiUkVTVEFVUkFETy4iIDogIj4+IERSWS1SVU4uIFJvZGUgY29tIENPTkZJUk09eWVzIHBhcmEgcmVzdGF1cmFyLiIK' | base64 -d > /app/fin_soft_restore.rb

# dry-run e depois confirmar:
ACCOUNT_ID=21 SINCE="2026-06-02 15:44" RAILS_ENV=production bundle exec rails runner /app/fin_soft_restore.rb
ACCOUNT_ID=21 SINCE="2026-06-02 15:44" CONFIRM=yes RAILS_ENV=production bundle exec rails runner /app/fin_soft_restore.rb
```

---

## B) HARD DELETE (permanente, irreversível)

> Use só se quiser purga física. **Não tem volta.** Mesma estrutura: ordem filho→pai (FKs são todas `on_delete: :restrict`), anula auto-referências antes, guarda de multi-tenancy, transação.

**1. Gravar o script:**

```bash
echo 'YWlkID0gSW50ZWdlcihFTlYuZmV0Y2goIkFDQ09VTlRfSUQiKSkgICAjIG9icmlnYXRvcmlvOyBzZW0gZGVmYXVsdApjb25maXJtID0gRU5WWyJDT05GSVJNIl0gPT0gInllcyIKQWN0aXZlUmVjb3JkOjpCYXNlLmxvZ2dlciA9IG5pbApvcmRlciA9IFsKICBbInBheW1lbnRfcmVjZWlwdF9pdGVtcyIsIEZpbmFuY2lhbDo6UGF5bWVudFJlY2VpcHRJdGVtXSwgWyJjb21taXNzaW9uX2VudHJpZXMiLCBGaW5hbmNpYWw6OkNvbW1pc3Npb25FbnRyeV0sCiAgWyJyZWZ1bmRzIiwgRmluYW5jaWFsOjpSZWZ1bmRdLCBbInBhdGllbnRfY3JlZGl0cyIsIEZpbmFuY2lhbDo6UGF0aWVudENyZWRpdF0sCiAgWyJjYXNoX21vdmVtZW50cyIsIEZpbmFuY2lhbDo6Q2FzaE1vdmVtZW50XSwgWyJidWRnZXRfaXRlbXMiLCBGaW5hbmNpYWw6OkJ1ZGdldEl0ZW1dLAogIFsicGF5bWVudF9yZWNlaXB0cyIsIEZpbmFuY2lhbDo6UGF5bWVudFJlY2VpcHRdLCBbImVudHJpZXMiLCBGaW5hbmNpYWw6OkVudHJ5XSwKICBbImluc3RhbGxtZW50cyIsIEZpbmFuY2lhbDo6SW5zdGFsbG1lbnRdLCBbImV4cGVuc2VzIiwgRmluYW5jaWFsOjpFeHBlbnNlXSwKICBbInJlY3VycmluZ19leHBlbnNlcyIsIEZpbmFuY2lhbDo6UmVjdXJyaW5nRXhwZW5zZV0sIFsiYnVkZ2V0cyIsIEZpbmFuY2lhbDo6QnVkZ2V0XSwKICBbImNhc2hfcmVnaXN0ZXJzIiwgRmluYW5jaWFsOjpDYXNoUmVnaXN0ZXJdLCBbInJlY3VycmluZ19iaWxsaW5ncyIsIEZpbmFuY2lhbDo6UmVjdXJyaW5nQmlsbGluZ10KXQpvdGhlcnNfYmVmb3JlID0gRmluYW5jaWFsOjpFbnRyeS51bnNjb3BlZC53aGVyZS5ub3QoYWNjb3VudF9pZDogYWlkKS5jb3VudApwdXRzICI9PT0gSEFSRCBERUxFVEUgKFBFUk1BTkVOVEUpIGxhbmNhbWVudG9zIGFjY291bnQgI3thaWR9IC0gbW9kbzogI3tjb25maXJtID8gJ0VYRUNVQ0FPJyA6ICdEUlktUlVOJ30gPT09IgpwdXRzICJBVEVOQ0FPOiBoYXJkIGRlbGV0ZSBOQU8gZSByZXZlcnNpdmVsLiIKcHV0cyAiIgpvcmRlci5lYWNoIHsgfGxhYmVsLCBrfCBwdXRzIGZvcm1hdCgiICAlLTIycyBBQ0M9JS02ZCBPVVRSQVM9JWQiLCBsYWJlbCwgay51bnNjb3BlZC53aGVyZShhY2NvdW50X2lkOiBhaWQpLmNvdW50LCBrLnVuc2NvcGVkLndoZXJlLm5vdChhY2NvdW50X2lkOiBhaWQpLmNvdW50KSB9CnVubGVzcyBjb25maXJtCiAgcHV0cyAiIgogIHB1dHMgIj4+IERSWS1SVU46IG5hZGEgYXBhZ2Fkby4gUm9kZSBjb20gQ09ORklSTT15ZXMgcGFyYSBIQVJEIERFTEVURSBQRVJNQU5FTlRFLiIKICBleGl0IDAKZW5kCnJlcyA9IHt9CkFjdGl2ZVJlY29yZDo6QmFzZS50cmFuc2FjdGlvbiBkbwogIEZpbmFuY2lhbDo6RW50cnkudW5zY29wZWQud2hlcmUoYWNjb3VudF9pZDogYWlkKS51cGRhdGVfYWxsKHJldmVyc2VzX2VudHJ5X2lkOiBuaWwsIHRyYW5zZmVyX3BhaXJfaWQ6IG5pbCkKICBGaW5hbmNpYWw6Okluc3RhbGxtZW50LnVuc2NvcGVkLndoZXJlKGFjY291bnRfaWQ6IGFpZCkudXBkYXRlX2FsbChyZW5lZ290aWF0ZWRfdG9faWQ6IG5pbCwgcmVwbGFjZXNfaW5zdGFsbG1lbnRfaWQ6IG5pbCkKICBGaW5hbmNpYWw6OkNvbW1pc3Npb25FbnRyeS51bnNjb3BlZC53aGVyZShhY2NvdW50X2lkOiBhaWQpLnVwZGF0ZV9hbGwocmV2ZXJzZXNfY29tbWlzc2lvbl9lbnRyeV9pZDogbmlsKQogIEZpbmFuY2lhbDo6RXhwZW5zZS51bnNjb3BlZC53aGVyZShhY2NvdW50X2lkOiBhaWQpLnVwZGF0ZV9hbGwocGFyZW50X2V4cGVuc2VfaWQ6IG5pbCkKICBvcmRlci5lYWNoIHsgfGxhYmVsLCBrfCByZXNbbGFiZWxdID0gay51bnNjb3BlZC53aGVyZShhY2NvdW50X2lkOiBhaWQpLmRlbGV0ZV9hbGwgfQogIG9hID0gRmluYW5jaWFsOjpFbnRyeS51bnNjb3BlZC53aGVyZS5ub3QoYWNjb3VudF9pZDogYWlkKS5jb3VudAogIHJhaXNlICJBQk9SVDogT1VUUkFTIGNvbnRhcyBtdWRhcmFtICgje290aGVyc19iZWZvcmV9IC0+ICN7b2F9KSEiIGlmIG9hICE9IG90aGVyc19iZWZvcmUKZW5kCnB1dHMgIiIKcHV0cyAiPT09IEhBUkQtREVMRVRBRE8gPT09IjsgcmVzLmVhY2ggeyB8a2ssIHZ8IHB1dHMgZm9ybWF0KCIgICUtMjJzICVkIiwga2ssIHYpIH0KcHV0cyAiIgpwdXRzICJWZXJpZmljYWNhbyAodW5zY29wZWQsIGVzcGVyYWRvIDApOiIKb3JkZXIuZWFjaCB7IHxsYWJlbCwga3wgcHV0cyBmb3JtYXQoIiAgJS0yMnMgJWQiLCBsYWJlbCwgay51bnNjb3BlZC53aGVyZShhY2NvdW50X2lkOiBhaWQpLmNvdW50KSB9CnB1dHMgIiIKcHV0cyAiT1VUUkFTIGVudHJpZXMgaW50YWN0YXM6ICN7RmluYW5jaWFsOjpFbnRyeS51bnNjb3BlZC53aGVyZS5ub3QoYWNjb3VudF9pZDogYWlkKS5jb3VudH0gKGVyYSAje290aGVyc19iZWZvcmV9KSIKcHV0cyAiSEFSRCBERUxFVEUgY29uY2x1aWRvLiBOQU8gcmV2ZXJzaXZlbC4iCg==' | base64 -d > /app/fin_hard_reset.rb
```

**2. DRY-RUN:**

```bash
ACCOUNT_ID=21 RAILS_ENV=production bundle exec rails runner /app/fin_hard_reset.rb
```

**3. Executar (PERMANENTE):**

```bash
ACCOUNT_ID=21 CONFIRM=yes RAILS_ENV=production bundle exec rails runner /app/fin_hard_reset.rb
```

---

## Pós-execução

- Conferir na UI: **Financeiro › Fluxo de Caixa** (saldo R$ 0, sem lançamentos), **A Receber** (vazio), **A Pagar**, **DRE**, e a aba **Financeiro** dos pacientes.
- Limpar os scripts do container (opcional): `rm /app/fin_soft_reset.rb /app/fin_hard_reset.rb /app/fin_soft_restore.rb`

## Gotchas / por que funciona

- **Saldo Estimado e Saldo do Fluxo NÃO são armazenados** — calculados de `entries` (`initial_balance_cents + Σin − Σout`, só `affects_cashflow` e `cash_date <= hoje`). Apagar/ocultar entries zera. O "saldo inicial" é `financial_bank_accounts.initial_balance_cents` (BIGINT centavos) e tem tela própria (Configurações › Contas Bancárias).
- **Soft delete (`Financial::Concerns::SoftDeletable`):** `default_scope { where(deleted_at: nil) }`. Por isso os scripts usam `unscoped` — pra contar/atingir também o que já estava soft-deletado e ainda segura FK.
- **Hard delete exige ordem:** todas as FKs do módulo são `on_delete: :restrict`; é preciso apagar filho→pai e anular auto-refs antes (`entries.transfer_pair_id`/`reverses_entry_id`, `installments.renegotiated_to_id`/`replaces_installment_id`, `commission_entries.reverses_commission_entry_id`, `expenses.parent_expense_id`).
- **Nenhuma tabela fora de `financial_*` referencia o módulo** (só `transactions.financial_estimate_id`, sem FK) → não quebra agenda/pacientes.
- `recurring_billings`/`recurring_expenses` são templates (config-like) mas geram lançamentos; em reset de teste são incluídos pra não repopular via cron de produção.
- `payment_receipt_items` e `budget_items` não têm `deleted_at` → no soft delete ficam ocultos junto com o recibo/orçamento pai; no hard delete são removidos.

## Histórico

- **2026-06-02** — account 21 (Clínica Streit), soft delete: 10 entries, 2 recibos, 7 parcelas, 2 despesas, 4 orçamentos, 2 despesas fixas. Saldo R$ 3.075,45 → R$ 0,00. Outras contas intactas (3292 entries).
