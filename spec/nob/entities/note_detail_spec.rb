require "spec_helper"

RSpec.describe Nob::Entities::NoteDetail do
  let(:note) { Nob::Entities::Note.new(absolute_path: "/v/a.md", relative_path: "a.md") }

  it "exposes note/size/chars/frontmatter as keyword-initialized attributes" do
    detail = described_class.new(note: note, size: 10, chars: 8, frontmatter: {"k" => "v"})

    expect(detail.note).to(eq(note))
    expect(detail.size).to(eq(10))
    expect(detail.chars).to(eq(8))
    expect(detail.frontmatter).to(eq("k" => "v"))
  end

  it "treats two details with the same fields as equal" do
    a = described_class.new(note: note, size: 1, chars: 1, frontmatter: {})
    b = described_class.new(note: note, size: 1, chars: 1, frontmatter: {})

    expect(a).to(eq(b))
  end
end
