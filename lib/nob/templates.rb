module Nob
  module Templates
    class UndefinedVariable < Nob::Error; end
    class ParseError        < Nob::Error; end

    Token = Module.new

    Literal  = Struct.new(:text)     { include Token }
    Variable = Struct.new(:operator) { include Token }
  end
end
