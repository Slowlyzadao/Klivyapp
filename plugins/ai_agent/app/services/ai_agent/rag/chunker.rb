# Splits raw text into a parent/child hierarchy.
#
#   parents are ~1500 chars, broken at paragraph boundaries when possible
#   children are ~300 chars with 50-char overlap, broken at sentence boundaries
#
# Token-counting would be more precise, but char-counting keeps the
# plugin free of tiktoken/transformer deps. With a 4 chars ≈ 1 token
# heuristic, parent ≈ 375 tokens and child ≈ 75 tokens — well within the
# ranges recommended by Weaviate/Dify for parent/child RAG.
class AiAgent::Rag::Chunker
  DEFAULT_PARENT_SIZE = 1500
  DEFAULT_CHILD_SIZE  = 300
  DEFAULT_CHILD_OVERLAP = 50

  Result = Struct.new(:parents, keyword_init: true)
  ParentBlock = Struct.new(:position, :content, :children, keyword_init: true)
  ChildBlock  = Struct.new(:position, :content, keyword_init: true)

  def initialize(text, parent_size: DEFAULT_PARENT_SIZE,
                 child_size: DEFAULT_CHILD_SIZE,
                 child_overlap: DEFAULT_CHILD_OVERLAP)
    @text = text.to_s
    @parent_size = parent_size
    @child_size = child_size
    @child_overlap = child_overlap
  end

  def call
    normalized = normalize(@text)
    parent_blocks = split_into_parents(normalized)

    parents = parent_blocks.each_with_index.map do |parent_text, parent_idx|
      children = split_into_children(parent_text).each_with_index.map do |child_text, child_idx|
        ChildBlock.new(position: child_idx, content: child_text)
      end

      ParentBlock.new(position: parent_idx, content: parent_text, children: children)
    end

    Result.new(parents: parents)
  end

  private

  def normalize(text)
    # Collapse repeated whitespace, normalize line endings, strip control chars.
    text.gsub(/\r\n?/, "\n")
        .gsub(/[ \t]+/, ' ')
        .gsub(/\n{3,}/, "\n\n")
        .strip
  end

  def split_into_parents(text)
    # Prefer paragraph (double newline) boundaries, then fall back to size.
    paragraphs = text.split(/\n{2,}/).reject(&:blank?)
    accumulate(paragraphs, @parent_size, separator: "\n\n")
  end

  def split_into_children(parent_text)
    sentences = parent_text.scan(/[^.!?]+[.!?]+|\S[^\n]*\Z/).map(&:strip).reject(&:blank?)
    return [parent_text] if sentences.empty?

    chunks = accumulate(sentences, @child_size, separator: ' ')
    return chunks if @child_overlap.zero? || chunks.length <= 1

    with_overlap(chunks, @child_overlap)
  end

  def accumulate(units, target_size, separator:)
    chunks = []
    current = +''

    units.each do |unit|
      if current.empty?
        current << unit
      elsif current.length + separator.length + unit.length <= target_size
        current << separator << unit
      else
        chunks << current
        current = +unit.dup
      end
    end

    chunks << current unless current.empty?
    chunks
  end

  def with_overlap(chunks, overlap)
    chunks.each_with_index.map do |chunk, i|
      next chunk if i.zero?

      previous_tail = chunks[i - 1].last(overlap)
      "#{previous_tail} #{chunk}"
    end
  end
end
