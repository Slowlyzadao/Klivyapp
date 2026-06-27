// Validadores de contato (e-mail e telefone BR). Fonte única reusada no
// cadastro de paciente (modal Novo Paciente + aba Cadastro) e onde mais
// precisar. Funções puras, sem dependências — espelham o padrão de cpfHelpers.

// Exige local@dominio.tld com TLD de ≥2 letras. Mais estrito que o
// type="email" nativo e que o URI::MailTo::EMAIL_REGEXP do backend, que
// aceitam domínio sem ponto (ex.: "teste@mensa" passava direto).
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[a-zA-Z]{2,}$/;

export const isValidEmail = email => EMAIL_RE.test(String(email || '').trim());

// Dígitos nacionais do telefone (sem DDI). Remove o 55 só quando o número
// claramente tem DDI (12-13 dígitos) — não confunde com DDD 55 (RS), que num
// número nacional já fica com 11 dígitos.
export const nationalPhoneDigits = phone => {
  let digits = String(phone || '').replace(/\D/g, '');
  if (digits.length > 11 && digits.startsWith('55')) digits = digits.slice(2);
  return digits;
};

// Telefone BR válido: DDD + número, 10 dígitos (fixo) ou 11 (celular).
// Rejeita números truncados (ex.: "+55 1").
export const isValidBrazilianPhone = phone => {
  const len = nationalPhoneDigits(phone).length;
  return len === 10 || len === 11;
};
