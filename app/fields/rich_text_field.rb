require 'administrate/field/base'

class RichTextField < Administrate::Field::Base
  def to_s
    data.to_s
  end

  def preview
    plain = ActionView::Base.full_sanitizer.sanitize(data.to_s)
    plain.length > 120 ? "#{plain[0, 120]}…" : plain
  end
end
