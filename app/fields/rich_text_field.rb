require 'administrate/field/base'

class RichTextField < Administrate::Field::Base
  def to_s
    data.to_s.gsub(/<[^>]*>/, ' ').squish.truncate(120)
  end
end
