module Nob
  module Templates
    class UndefinedVariable < Nob::Error; end
    class ParseError < Nob::Error; end

    Literal = Struct.new(:text)
    Variable = Struct.new(:operator)
  end
end
