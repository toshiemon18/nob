require "spec_helper"

RSpec.describe Nob::Entities::Note do
  it "exposes absolute_path and relative_path as keyword-initialized attributes" do
    note = described_class.new(
      absolute_path: "/vault/foo.md",
      relative_path: "foo.md"
    )

    expect(note.absolute_path).to(eq("/vault/foo.md"))
    expect(note.relative_path).to(eq("foo.md"))
  end

  it "treats two notes with the same paths as equal" do
    a = described_class.new(absolute_path: "/v/a.md", relative_path: "a.md")
    b = described_class.new(absolute_path: "/v/a.md", relative_path: "a.md")

    expect(a).to(eq(b))
  end
end
