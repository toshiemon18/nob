require "spec_helper"

RSpec.describe Nob::Links do
  describe ".extract" do
    def link(raw, target, line)
      Nob::Links::Link.new(raw: raw, target: target, line: line)
    end

    it "extracts a [[name]] link with its line number" do
      expect(described_class.extract("see [[Plan]]\n")).to(eq([link("[[Plan]]", "Plan", 1)]))
    end

    it "extracts every link in order, numbering lines from 1" do
      text = "[[a]] and [[b]]\nnone\n[[c]]\n"

      expect(described_class.extract(text)).to(
        eq([link("[[a]]", "a", 1), link("[[b]]", "b", 1), link("[[c]]", "c", 3)])
      )
    end

    it "takes the target before an alias, a heading, or a block reference" do
      text = "[[Plan|計画]] [[Plan#Goals]] [[Plan#^abc123]] [[Plan#Goals|目標]]\n"

      expect(described_class.extract(text).map(&:target)).to(eq(["Plan", "Plan", "Plan", "Plan"]))
      expect(described_class.extract(text).map(&:raw).first).to(eq("[[Plan|計画]]"))
    end

    it "keeps the leading ! of an embed in the raw text" do
      expect(described_class.extract("![[diagram.png]]\n")).to(eq([link("![[diagram.png]]", "diagram.png", 1)]))
    end

    it "skips links without a name, such as a heading in the same note" do
      expect(described_class.extract("[[#Goals]] [[|alias]] [[ ]]\n")).to(eq([]))
    end

    it "strips spaces around the target" do
      expect(described_class.extract("[[ Plan | 計画 ]]\n").map(&:target)).to(eq(["Plan"]))
    end

    context("with frontmatter") do
      it "skips links in the frontmatter but keeps counting its lines" do
        text = "---\nrelated: \"[[A]]\"\n---\n[[B]]\n"

        expect(described_class.extract(text)).to(eq([link("[[B]]", "B", 4)]))
      end

      it "treats the whole text as body when the frontmatter is not closed" do
        expect(described_class.extract("---\n[[A]]\n")).to(eq([link("[[A]]", "A", 2)]))
      end

      it "only treats a --- on the first line as frontmatter" do
        expect(described_class.extract("intro\n---\n[[A]]\n---\n").map(&:target)).to(eq(["A"]))
      end
    end

    context("with code") do
      it "skips links inside fenced code blocks" do
        text = "```\n[[A]]\n```\n~~~ruby\n[[B]]\n~~~\n[[C]]\n"

        expect(described_class.extract(text)).to(eq([link("[[C]]", "C", 7)]))
      end

      it "closes a fence only with the same character and at least the same length" do
        text = "````\n```\n[[A]]\n~~~~\n````\n[[B]]\n"

        expect(described_class.extract(text).map(&:target)).to(eq(["B"]))
      end

      it "treats an unclosed fence as code to the end" do
        expect(described_class.extract("```\n[[A]]\n")).to(eq([]))
      end

      it "skips links inside inline code" do
        text = "`[[A]]` [[B]] ``x ` [[C]]`` [[D]]\n"

        expect(described_class.extract(text).map(&:target)).to(eq(["B", "D"]))
      end
    end
  end
end
