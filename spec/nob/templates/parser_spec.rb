require "spec_helper"

RSpec.describe Nob::Templates::Parser do
  let(:literal)  { Nob::Templates::Literal }
  let(:variable) { Nob::Templates::Variable }
  let(:title_op) { Nob::Templates::Operators::Title }
  let(:date_op)  { Nob::Templates::Operators::Date }
  let(:time_op)  { Nob::Templates::Operators::Time }

  describe ".parse" do
    context "literals and basic variables" do
      it "returns a single Literal for plain text" do
        expect(described_class.parse("hello world")).to eq(
          [literal.new("hello world")]
        )
      end

      it "returns empty array for empty string" do
        expect(described_class.parse("")).to eq([])
      end

      it "parses a single variable" do
        expect(described_class.parse("{{title}}")).to eq(
          [variable.new(title_op.new(nil))]
        )
      end

      it "parses literal/variable/literal mix" do
        expect(described_class.parse("# {{title}}\n")).to eq(
          [literal.new("# "), variable.new(title_op.new(nil)), literal.new("\n")]
        )
      end

      it "treats stand-alone }} as a literal" do
        expect(described_class.parse("hello }} world")).to eq(
          [literal.new("hello }} world")]
        )
      end

      it "treats stand-alone single { as a literal" do
        expect(described_class.parse("a { b")).to eq([literal.new("a { b")])
      end

      it "treats stand-alone single } as a literal" do
        expect(described_class.parse("a } b")).to eq([literal.new("a } b")])
      end
    end

    context "format spec parsing (split + strip)" do
      it "splits on the first colon only" do
        tokens = described_class.parse("{{time:%H:%M:%S}}")
        expect(tokens).to eq([variable.new(time_op.new("%H:%M:%S"))])
      end

      it "strips whitespace around name and fmt" do
        tokens = described_class.parse("{{ date : %Y-%m-%d }}")
        expect(tokens).to eq([variable.new(date_op.new("%Y-%m-%d"))])
      end

      it "treats no-colon body as name without fmt" do
        tokens = described_class.parse("{{date}}")
        expect(tokens).to eq([variable.new(date_op.new(nil))])
      end
    end

    context "line number tracking" do
      it "reports the start line of an unterminated variable" do
        expect { described_class.parse("line1\nline2 {{ unterminated") }.to raise_error(
          Nob::Templates::ParseError, /\(line 2\)/
        )
      end

      it "reports the line of the variable for unknown variables" do
        expect { described_class.parse("a\nb\nc {{foo}}") }.to raise_error(
          Nob::Templates::UndefinedVariable, /\(line 3\)/
        )
      end

      it "uses the start line of {{ when variable body spans newlines" do
        expect { described_class.parse("x\n{{ foo\n}}") }.to raise_error(
          Nob::Templates::UndefinedVariable, /\(line 2\)/
        )
      end
    end

    context "error cases" do
      it "raises ParseError on unterminated variable" do
        expect { described_class.parse("hi {{title") }.to raise_error(
          Nob::Templates::ParseError, /unterminated variable/
        )
      end

      it "raises ParseError on nested {{ inside variable" do
        expect { described_class.parse("{{ {{ x }} }}") }.to raise_error(
          Nob::Templates::ParseError, /unexpected '\{\{' inside variable/
        )
      end

      it "raises ParseError on empty variable {{}}" do
        expect { described_class.parse("{{}}") }.to raise_error(
          Nob::Templates::ParseError, /empty variable/
        )
      end

      it "raises ParseError on whitespace-only variable {{   }}" do
        expect { described_class.parse("{{   }}") }.to raise_error(
          Nob::Templates::ParseError, /empty variable/
        )
      end
    end

    context "realistic templates" do
      it "parses a daily-note template (frontmatter + heading + variables)" do
        template = <<~TPL
          ---
          title: {{title}}
          created: {{date}}
          id: {{id}}
          ---

          # {{title}}

          Started at {{time}}.
        TPL

        expect(described_class.parse(template)).to eq([
          literal.new("---\ntitle: "),
          variable.new(title_op.new(nil)),
          literal.new("\ncreated: "),
          variable.new(date_op.new(nil)),
          literal.new("\nid: "),
          variable.new(Nob::Templates::Operators::Id.new(nil)),
          literal.new("\n---\n\n# "),
          variable.new(title_op.new(nil)),
          literal.new("\n\nStarted at "),
          variable.new(time_op.new(nil)),
          literal.new(".\n")
        ])
      end

      it "parses a zettel-style template with custom formats" do
        template = "# {{title}}\n\n- created: {{date:%Y/%m/%d}} {{time:%H:%M:%S}}\n- id: {{id}}\n"

        expect(described_class.parse(template)).to eq([
          literal.new("# "),
          variable.new(title_op.new(nil)),
          literal.new("\n\n- created: "),
          variable.new(date_op.new("%Y/%m/%d")),
          literal.new(" "),
          variable.new(time_op.new("%H:%M:%S")),
          literal.new("\n- id: "),
          variable.new(Nob::Templates::Operators::Id.new(nil)),
          literal.new("\n")
        ])
      end

      it "parses a template that contains no variables" do
        template = "# Untitled\n\nWrite your note here.\n"
        expect(described_class.parse(template)).to eq([literal.new(template)])
      end
    end

    context "rewrapping UndefinedVariable from factory" do
      it "wraps unknown name with token text and line" do
        expect { described_class.parse("{{foo}}") }.to raise_error(
          Nob::Templates::UndefinedVariable,
          "unknown variable: foo: {{foo}} (line 1)"
        )
      end

      it "wraps title-with-fmt with token text and line" do
        expect { described_class.parse("a {{ title : %Y }}") }.to raise_error(
          Nob::Templates::UndefinedVariable,
          "title does not accept format: %Y: {{ title : %Y }} (line 1)"
        )
      end
    end
  end
end
