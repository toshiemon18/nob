require "spec_helper"

RSpec.describe Nob::Templates::Renderer do
  let(:now)   { Time.new(2026, 5, 3, 9, 7, 30) }
  let(:title) { "My Note" }

  describe ".render" do
    it "returns the input as-is when there is no variable" do
      expect(described_class.render("hello world", title: title, now: now)).to eq("hello world")
    end

    it "expands {{title}}" do
      expect(described_class.render("# {{title}}\n", title: title, now: now)).to eq("# My Note\n")
    end

    it "expands {{date}} with default format" do
      expect(described_class.render("{{date}}", title: title, now: now)).to eq("2026-05-03")
    end

    it "expands {{date:fmt}} with custom format" do
      expect(described_class.render("{{date:%Y/%m/%d}}", title: title, now: now)).to eq("2026/05/03")
    end

    it "expands {{time}} with default format" do
      expect(described_class.render("{{time}}", title: title, now: now)).to eq("09:07")
    end

    it "expands {{id}}" do
      expect(described_class.render("{{id}}", title: title, now: now)).to eq("20260503090730")
    end

    it "expands a full template containing frontmatter and body" do
      template = <<~TPL
        ---
        title: {{title}}
        created: {{date}}
        id: {{id}}
        ---

        # {{title}}

        Started at {{time}}.
      TPL
      expected = <<~OUT
        ---
        title: My Note
        created: 2026-05-03
        id: 20260503090730
        ---

        # My Note

        Started at 09:07.
      OUT
      expect(described_class.render(template, title: title, now: now)).to eq(expected)
    end

    it "raises UndefinedVariable for unknown variable" do
      expect { described_class.render("{{foo}}", title: title, now: now) }.to raise_error(
        Nob::Templates::UndefinedVariable, /unknown variable: foo/
      )
    end

    it "raises ParseError for unterminated variable" do
      expect { described_class.render("hi {{title", title: title, now: now) }.to raise_error(
        Nob::Templates::ParseError, /unterminated variable/
      )
    end
  end
end
