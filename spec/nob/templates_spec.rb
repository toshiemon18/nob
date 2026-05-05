require "spec_helper"
require "tmpdir"

RSpec.describe Nob::Templates do
  describe ".render" do
    let(:now) { Time.new(2026, 5, 5, 9, 0, 0) }
    let(:title) { "My Note" }

    it "returns an empty string when neither path nor text is given" do
      expect(described_class.render(path: nil, text: nil, title: title, now: now)).to eq("")
    end

    it "renders the given text directly" do
      expect(described_class.render(text: "# {{title}}\n", title: title, now: now)).to eq("# My Note\n")
    end

    it "reads the template at path and renders it" do
      Dir.mktmpdir("nob-templates") do |dir|
        path = File.join(dir, "tpl.md")
        File.write(path, "# {{title}}\n")

        expect(described_class.render(path: path, title: title, now: now)).to eq("# My Note\n")
      end
    end

    it "raises Nob::Error mentioning the path when path points at a missing file" do
      Dir.mktmpdir("nob-templates") do |dir|
        missing = File.join(dir, "absent.md")

        expect {
          described_class.render(path: missing, title: title, now: now)
        }.to raise_error(Nob::Error, /template file not found.*#{Regexp.escape(missing)}/)
      end
    end
  end

  describe Nob::Templates::UndefinedVariable do
    it "inherits from Nob::Error" do
      expect(described_class.ancestors).to include(Nob::Error)
    end
  end

  describe Nob::Templates::ParseError do
    it "inherits from Nob::Error" do
      expect(described_class.ancestors).to include(Nob::Error)
    end
  end

  describe Nob::Templates::Literal do
    it "compares by text" do
      expect(described_class.new("x")).to eq(described_class.new("x"))
      expect(described_class.new("x")).not_to eq(described_class.new("y"))
    end
  end

  describe Nob::Templates::Variable do
    it "compares by operator" do
      op1 = Nob::Templates::Operators::Date.new("%Y")
      op2 = Nob::Templates::Operators::Date.new("%Y")
      op3 = Nob::Templates::Operators::Date.new("%m")
      expect(described_class.new(op1)).to eq(described_class.new(op2))
      expect(described_class.new(op1)).not_to eq(described_class.new(op3))
    end
  end
end
