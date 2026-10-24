require "spec_helper"
require "tmpdir"

RSpec.describe Nob::Templates do
  describe ".render" do
    let(:now) { Time.new(2026, 5, 5, 9, 0, 0) }
    let(:title) { "My Note" }

    it "raises ArgumentError when neither path nor text is given" do
      expect {
        described_class.render(path: nil, text: nil, title: title, now: now)
      }
        .to(raise_error(ArgumentError, /specify path: or text:/))
    end

    it "raises ArgumentError when both path and text are given" do
      expect {
        described_class.render(path: "tpl.md", text: "x", title: title, now: now)
      }
        .to(raise_error(ArgumentError, /specify only one of path: or text:/))
    end

    it "renders the given text directly" do
      expect(described_class.render(text: "# {{title}}\n", title: title, now: now)).to(eq("# My Note\n"))
    end

    it "reads the template at path and renders it" do
      Dir.mktmpdir("nob-templates") do |dir|
        path = File.join(dir, "tpl.md")
        File.write(path, "# {{title}}\n")

        expect(described_class.render(path: path, title: title, now: now)).to(eq("# My Note\n"))
      end
    end

    it "raises Nob::Error mentioning the path when path points at a missing file" do
      Dir.mktmpdir("nob-templates") do |dir|
        missing = File.join(dir, "absent.md")

        expect {
          described_class.render(path: missing, title: title, now: now)
        }
          .to(raise_error(Nob::Error, /template file not found.*#{Regexp.escape(missing)}/))
      end
    end
  end

  describe Nob::Templates::UndefinedVariable do
    it "inherits from Nob::Error" do
      expect(described_class.ancestors).to(include(Nob::Error))
    end
  end

  describe Nob::Templates::ParseError do
    it "inherits from Nob::Error" do
      expect(described_class.ancestors).to(include(Nob::Error))
    end
  end

  describe Nob::Templates::Literal do
    it "compares by text" do
      expect(described_class.new("x")).to(eq(described_class.new("x")))
      expect(described_class.new("x")).not_to(eq(described_class.new("y")))
    end
  end

  describe Nob::Templates::Variable do
    it "compares by operator" do
      op1 = Nob::Templates::Operators::Date.new("%Y")
      op2 = Nob::Templates::Operators::Date.new("%Y")
      op3 = Nob::Templates::Operators::Date.new("%m")
      expect(described_class.new(op1)).to(eq(described_class.new(op2)))
      expect(described_class.new(op1)).not_to(eq(described_class.new(op3)))
    end
  end

  describe ".locate" do
    let(:vault) { Dir.mktmpdir("nob-vault") }

    after { FileUtils.remove_entry(vault) }

    it "resolves a vault-relative path" do
      expect(described_class.locate(vault, "tpl/note.md", source: "--template")).to(eq(File.join(vault, "tpl/note.md")))
    end

    it "returns nil for a blank value" do
      expect(described_class.locate(vault, "", source: "--template")).to(be_nil)
      expect(described_class.locate(vault, nil, source: "--template")).to(be_nil)
    end

    it "rejects a path that escapes the vault, naming the source" do
      expect { described_class.locate(vault, "../../x.md", source: "--template") }.to(
        raise_error(Nob::Templates::InvalidPath, "template path escapes the vault: ../../x.md (--template)")
      )
    end

    it "rejects an absolute path, naming a config key as the source" do
      expect { described_class.locate(vault, "/etc/tpl.md", source: Nob::Config::Keys::NOTE_TEMPLATE) }.to(
        raise_error(Nob::Templates::InvalidPath, "template path must be relative to the vault: /etc/tpl.md ([note].template)")
      )
    end

    it "is a Nob::Error so the CLI reports it" do
      expect(Nob::Templates::InvalidPath.ancestors).to(include(Nob::Error))
    end
  end
end
