module Nob
  module Templates
    class UndefinedVariable < Nob::Error; end
    class ParseError < Nob::Error; end

    Literal = Struct.new(:text)
    Variable = Struct.new(:operator)

    def self.render(title:, now:, path: nil, text: nil)
      text ||= read_template(path)
      return "" if text.nil?
      Renderer.render(text, title: title, now: now)
    end

    def self.read_template(path)
      return nil if path.nil?
      unless File.exist?(path)
        raise Nob::Error, "template file not found: #{path}"
      end
      File.read(path)
    end
    private_class_method :read_template
  end
end
