# Gera variantes digit-only de um número brasileiro para suportar busca/lookup
# tolerante ao "9" inicial do celular.
#
# Em 2016 o Brasil padronizou o 9º dígito em celulares, mas:
# - Bases legadas têm contatos sem o 9 (12 dígitos: 55 + DDD + 8).
# - WhatsApp Web às vezes guarda o WID sem o 9 mesmo em mobiles.
# - Usuários frequentemente digitam o número COM o 9 a mais (13/14 dígitos).
#
# Este helper devolve um array de strings digit-only que cobre as formas
# plausíveis para o mesmo número. Consumidores aplicam ILIKE '%variant%' em
# `phone_number`/`identifier` (que ficam em E.164 ou JID — ambos contêm a
# sequência de dígitos como substring).
#
# Retorna [] quando o input não parece um telefone (curto/longo demais ou
# fora do formato Brasil), nesse caso o chamador faz fallback ao ILIKE direto.
class Whatsapp::PhoneSearchVariants
  def self.digit_variants(query)
    digits = query.to_s.gsub(/\D/, '')
    return [] if digits.length < 10 || digits.length > 14

    has_cc = digits.start_with?('55') && digits.length.between?(12, 14)
    local = has_cc ? digits[2..] : digits
    return [] unless local.length.between?(10, 12)

    ddd  = local[0, 2]
    rest = local[2..]

    variants = []
    case rest.length
    when 8
      # +DDD + 8 dígitos (fixo ou celular legado): também gera com "9" prefixado.
      variants << "55#{ddd}#{rest}"
      variants << "55#{ddd}9#{rest}"
    when 9
      variants << "55#{ddd}#{rest}"
      variants << "55#{ddd}#{rest[1..]}" if rest.start_with?('9')
    when 10
      # Usuário digitou um "9" a mais (ex: "21 9 9 8868-8681" → "2199 8868 8681").
      variants << "55#{ddd}#{rest}"
      if rest.start_with?('99')
        variants << "55#{ddd}#{rest[1..]}"
        variants << "55#{ddd}#{rest[2..]}"
      end
    end

    variants.uniq
  end
end
