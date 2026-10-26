require "stringio"
require "tmpdir"

RSpec.describe Nob::Cli do
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  describe "#version" do
    it "prints Nob::VERSION to stdout" do
      output = capture_stdout { described_class.start(["version"]) }

      expect(output).to(eq("#{Nob::VERSION}\n"))
    end
  end

  describe "#show" do
    context("with the fixture vault") do
      include_context("fixture vault")

      it "prints Path/Size/Chars and the frontmatter section for a note with frontmatter" do
        output = capture_stdout { described_class.start(["show", "Plan"]) }

        expect(output).to(include("Path     : projects/Plan.md\n"))
        expect(output).to(match(/^Size     : \d+B\n/))
        expect(output).to(match(/^Chars    : \d+\n/))
        expect(output).to(include("---frontmatter---\n"))
        expect(output).to(include("title    : Plan\n"))
        expect(output).to(include("date     : 2026-04-30\n"))
      end
    end

    context("with links") do
      include_context("tmp vault")

      def touch(relative_path, content = "")
        abs = File.join(@vault, relative_path)
        FileUtils.mkdir_p(File.dirname(abs))
        File.write(abs, content)
      end

      it "lists each distinct link once with its resolution, after the frontmatter" do
        touch("projects/Plan.md")
        touch("a/Note.md")
        touch("b/Note.md")
        touch("projects/Hub.md", "---\ntitle: Hub\n---\n[[Plan|計画]] [[missing]]\n[[Note]] [[Plan|計画]]\n")

        output = capture_stdout { described_class.start(["show", "Hub"]) }

        expect(output).to(
          end_with(
            "title    : Hub\n" \
              "---links---\n" \
              "[[Plan|計画]]  → projects/Plan.md\n" \
              "[[missing]]  → (unresolved)\n" \
              "[[Note]]     → (ambiguous: a/Note.md, b/Note.md)\n"
          )
        )
      end

      it "omits the links section when the note has no links" do
        touch("plain.md", "no links here\n")

        output = capture_stdout { described_class.start(["show", "plain"]) }

        expect(output).not_to(include("---links---"))
      end
    end

    context("with size formatting") do
      include_context("tmp vault")

      it "formats sub-1KB sizes in bytes" do
        File.write(File.join(@vault, "tiny.md"), "x" * 512)

        output = capture_stdout { described_class.start(["show", "tiny"]) }

        expect(output).to(include("Size     : 512B\n"))
      end

      it "omits the frontmatter section for a note without frontmatter" do
        File.write(File.join(@vault, "plain.md"), "no frontmatter here")

        output = capture_stdout { described_class.start(["show", "plain"]) }

        expect(output).to(include("Path     : plain.md\n"))
        expect(output).not_to(include("---frontmatter---"))
      end

      it "formats 1024 bytes as 1.0KB" do
        File.write(File.join(@vault, "kb.md"), "x" * 1024)

        output = capture_stdout { described_class.start(["show", "kb"]) }

        expect(output).to(include("Size     : 1.0KB\n"))
      end

      it "formats 1MB as 1.0MB" do
        File.write(File.join(@vault, "mb.md"), "x" * (1024 * 1024))

        output = capture_stdout { described_class.start(["show", "mb"]) }

        expect(output).to(include("Size     : 1.0MB\n"))
      end
    end

    context("with error conditions") do
      include_context("fixture vault")

      it "warns and exits 1 when the title does not match any note" do
        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["show", "missing"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(match(/Error.*missing/))
      end

      it "does not treat title metacharacters as glob patterns" do
        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["show", "*"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(match(/Error.*not found/))
      end
    end

    context("with title resolution edge cases") do
      include_context("tmp vault")

      def touch(relative_path, content = "")
        abs = File.join(@vault, relative_path)
        FileUtils.mkdir_p(File.dirname(abs))
        File.write(abs, content)
        abs
      end

      it "exits 1 for a note that is not valid UTF-8" do
        touch("bad.md", "")
        File.binwrite(File.join(@vault, "bad.md"), "[[x]] \xFF\n".b)

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["show", "bad"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(eq("Error: invalid UTF-8 in #{File.join(@vault, "bad.md")}\n"))
      end

      it "reads a note as UTF-8 regardless of the default external encoding" do
        touch("jp.md", "---\ntitle: 計画\n---\n[[計画]]\n")
        original = Encoding.default_external
        output = nil
        begin
          Encoding.default_external = Encoding::US_ASCII
          output = capture_stdout { described_class.start(["show", "jp"]) }
        ensure
          Encoding.default_external = original
        end

        expect(output).to(include("[[計画]]  → (unresolved)"))
      end

      it "reports an ambiguous title given as bytes, as ARGV is under LANG=C" do
        touch("計画.md", "a")
        touch("a/計画.md", "b")

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["show", "計画".b]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(include("a/計画.md"))
      end

      it "resolves the title case-insensitively" do
        touch("projects/Plan.md", "a")

        output = capture_stdout { described_class.start(["show", "plan"]) }

        expect(output).to(include("Path     : projects/Plan.md\n"))
      end

      it "reports notes differing only in case as ambiguous" do
        touch("projects/Plan.md", "a")
        touch("archive/plan.md", "b")

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["show", "PLAN"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(include("archive/plan.md"))
        expect(stderr).to(include("projects/Plan.md"))
      end

      it "ignores notes under dot-directories when resolving the title" do
        touch(".cache/note.md", "x")

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["show", "note"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(match(/Error.*not found/))
      end

      it "warns with candidate paths sorted by basename then path on ambiguity" do
        touch("projects/Plan.md", "a")
        touch("archive/Plan.md", "b")

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["show", "Plan"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(include("archive/Plan.md"))
        expect(stderr).to(include("projects/Plan.md"))
        expect(stderr.index("archive/Plan.md")).to(be < stderr.index("projects/Plan.md"))
      end
    end
  end

  describe "#config" do
    context("with -e") do
      before do
        @cfg_dir = Dir.mktmpdir("nob-cfg")
        @config_path = File.join(@cfg_dir, "nob", "config.toml")
        allow(Nob::Config).to(receive(:default_path).and_return(@config_path))
      end

      after do
        FileUtils.remove_entry(@cfg_dir) if @cfg_dir
      end

      it "ensures the config file exists and delegates to Editor.open" do
        expect(Nob::Config).to(receive(:ensure_exists).with(@config_path).ordered.and_call_original)
        expect(Nob::Config::Editor).to(receive(:open).with(path: @config_path).ordered)

        described_class.start(["config", "-e"])
      end
    end

    context("with --path") do
      before do
        @cfg_dir = Dir.mktmpdir("nob-cfg")
        @config_path = File.join(@cfg_dir, "nob", "config.toml")
        allow(Nob::Config).to(receive(:default_path).and_return(@config_path))
      end

      after do
        FileUtils.remove_entry(@cfg_dir) if @cfg_dir
      end

      it "ensures the config file exists and prints its path" do
        expect(Nob::Config).to(receive(:ensure_exists).with(@config_path).and_call_original)

        output = capture_stdout { described_class.start(["config", "--path"]) }

        expect(output).to(eq("#{@config_path}\n"))
      end
    end

    context("with --show") do
      before do
        @cfg_dir = Dir.mktmpdir("nob-cfg")
        @config_path = File.join(@cfg_dir, "nob", "config.toml")
        FileUtils.mkdir_p(File.dirname(@config_path))
        File.write(@config_path, "vault = \"/some/where\"\n")
        allow(Nob::Config).to(receive(:default_path).and_return(@config_path))
      end

      after do
        FileUtils.remove_entry(@cfg_dir) if @cfg_dir
      end

      it "prints the config file contents to stdout as-is" do
        output = capture_stdout { described_class.start(["config", "--show"]) }

        expect(output).to(eq("vault = \"/some/where\"\n"))
      end
    end

    context("without options") do
      it "prints an Error-prefixed message and exits 1" do
        stderr = capture_stderr do
          expect {
            described_class.start(["config"])
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(match(/^Error: specify -e\/--path\/--show/))
      end
    end

    context("with conflicting flags") do
      [
        ["config", "-e", "--path"],
        ["config", "--path", "--show"],
        ["config", "-e", "--show"],
        ["config", "-e", "--path", "--show"]
      ].each do |args|
        it "rejects #{args.drop(1).join(" ")} with Error and exits 1" do
          stderr = capture_stderr do
            expect {
              described_class.start(args)
            }
              .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
          end

          expect(stderr).to(match(/Error: specify only one of -e\/--path\/--show/))
        end
      end
    end

    context("when Editor.open raises Nob::Error") do
      before do
        @cfg_dir = Dir.mktmpdir("nob-cfg")
        config_path = File.join(@cfg_dir, "nob", "config.toml")
        allow(Nob::Config).to(receive(:default_path).and_return(config_path))
        allow(Nob::Config).to(receive(:ensure_exists))
        allow(Nob::Config::Editor).to(receive(:open).and_raise(Nob::Error, "failed to launch editor: foo"))
      end

      after do
        FileUtils.remove_entry(@cfg_dir) if @cfg_dir
      end

      it "warns and exits 1" do
        stderr = capture_stderr do
          expect {
            described_class.start(["config", "-e"])
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(match(/Error: failed to launch editor/))
      end
    end
  end

  describe "#create" do
    include_context("tmp vault")

    it "describes --template as overriding [note].template in the help" do
      output = capture_stdout { described_class.start(["help", "create"]) }

      expect(output).to(include("Vault-relative template path (overrides [note].template)"))
    end

    it "prints Created: <path> for a fresh note" do
      output = capture_stdout { described_class.start(["create", "FreshNote"]) }

      expect(output).to(eq("Created: #{File.join(@vault, "FreshNote.md")}\n"))
    end

    it "prints Recreated: <path> (backup: ...) when --force backs up an existing note" do
      capture_stdout { described_class.start(["create", "Dup"]) }

      output = capture_stdout { described_class.start(["create", "Dup", "--force"]) }

      expect(output).to(match(%r{\ARecreated: .*/Dup\.md \(backup: .*Dup\.backup-\d{8}-\d{6}\.md\)\n\z}))
    end

    it "writes a quoted title/date frontmatter when no template is configured" do
      capture_stdout { described_class.start(["create", "会議: 定例"]) }

      content = File.read(File.join(@vault, "会議: 定例.md"))
      expect(content).to(match(/\A---\ntitle: '会議: 定例'\ndate: \d{4}-\d{2}-\d{2}\n---\n\n\z/))
    end

    context("with [note].template configured") do
      def configure_note_template(template_body, path: "templates/note.md")
        if template_body
          abs = File.join(@vault, path)
          FileUtils.mkdir_p(File.dirname(abs))
          File.write(abs, template_body)
        end

        write_config(
          <<~TOML
            vault = "#{@vault}"
            [note]
            template = "#{path}"
          TOML
        )
      end

      it "writes the rendered template verbatim" do
        configure_note_template("---\ntitle: \"{{title}}\"\n---\n# {{title}}\n")

        capture_stdout { described_class.start(["create", "Meeting"]) }

        expect(File.read(File.join(@vault, "Meeting.md"))).to(eq("---\ntitle: \"Meeting\"\n---\n# Meeting\n"))
      end

      it "prefers --template (vault-relative) over [note].template" do
        configure_note_template("from config\n")
        FileUtils.mkdir_p(File.join(@vault, "templates"))
        File.write(File.join(@vault, "templates/meeting.md"), "meeting: {{title}}\n")

        capture_stdout { described_class.start(["create", "Weekly", "--template", "templates/meeting.md"]) }

        expect(File.read(File.join(@vault, "Weekly.md"))).to(eq("meeting: Weekly\n"))
      end

      it "exits 1 naming --template when it escapes the vault" do
        configure_note_template("from config\n")

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["create", "Weekly", "-t", "../outside.md"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(include("Error: template path escapes the vault: ../outside.md (--template)"))
        expect(File.exist?(File.join(@vault, "Weekly.md"))).to(be(false))
      end

      it "exits 1 naming [note].template when it escapes the vault" do
        configure_note_template(nil, path: "../note.md")

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["create", "Weekly"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(include("Error: template path escapes the vault: ../note.md ([note].template)"))
        expect(File.exist?(File.join(@vault, "Weekly.md"))).to(be(false))
      end

      it "exits 1 without creating the note when the template file is missing" do
        configure_note_template(nil, path: "templates/missing.md")

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["create", "Meeting"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(match(%r{Error: template file not found: .*templates/missing\.md}))
        expect(File.exist?(File.join(@vault, "Meeting.md"))).to(be(false))
      end

      it "exits 1 without creating the note when the template has a syntax error" do
        configure_note_template("# {{unknown}}\n")

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["create", "Meeting"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(match(/^Error: .*unknown/))
        expect(File.exist?(File.join(@vault, "Meeting.md"))).to(be(false))
      end

      it "leaves the existing note untouched and makes no backup when --force fails to render" do
        configure_note_template("# {{unknown}}\n")
        existing = File.join(@vault, "Meeting.md")
        File.write(existing, "original\n")

        capture_stderr do
          expect {
            capture_stdout { described_class.start(["create", "Meeting", "--force"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(File.read(existing)).to(eq("original\n"))
        expect(Dir.glob(File.join(@vault, "Meeting.backup-*.md"))).to(be_empty)
      end
    end

    it "creates the note under --dir, making the directories" do
      output = capture_stdout { described_class.start(["create", "Plan", "--dir", "projects/2026"]) }

      path = File.join(@vault, "projects/2026", "Plan.md")
      expect(output).to(eq("Created: #{path}\n"))
      expect(File.exist?(path)).to(be(true))
    end

    it "exits 1 without writing when --dir escapes the vault" do
      escaped_dir = File.join(File.dirname(@vault), "escaped")

      stderr = capture_stderr do
        expect {
          capture_stdout { described_class.start(["create", "x", "--dir", "../escaped"]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(include("Error: path escapes the vault: ../escaped/x.md"))
      expect(File.exist?(escaped_dir)).to(be(false))
    end

    it "exits 1 without writing when the title escapes the vault" do
      evil_path = File.join(File.dirname(@vault), "evil.md")

      stderr = capture_stderr do
        expect {
          capture_stdout { described_class.start(["create", "../evil"]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(include("Error: path escapes the vault: ../evil.md"))
      expect(File.exist?(evil_path)).to(be(false))
    end

    it "exits 1 without writing when --dir is an absolute path" do
      outside = Dir.mktmpdir("nob-outside")

      stderr = capture_stderr do
        expect {
          capture_stdout { described_class.start(["create", "x", "--dir", outside]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(include("Error: path must be relative to the vault: #{outside}"))
      expect(Dir.children(outside)).to(be_empty)
      expect(Dir.children(@vault)).to(be_empty)
    ensure
      FileUtils.remove_entry(outside) if outside
    end
  end

  describe "#daily" do
    include_context("tmp vault")

    it "creates today's daily note and prints Created:" do
      output = nil
      capture_stderr { output = capture_stdout { described_class.start(["daily"]) } }

      expect(output).to(match(/^Created: .*\/daily\/\d{4}-\d{2}-\d{2}\.md\n/))
    end

    it "prints Already exists: on the second run" do
      capture_stderr { capture_stdout { described_class.start(["daily"]) } }
      File.write(Dir.glob("#{@vault}/daily/*.md").first, "user content\n")

      output = nil
      capture_stderr { output = capture_stdout { described_class.start(["daily"]) } }

      expect(output).to(match(/^Already exists: /))
    end

    it "renders the template into an existing empty note without a backup" do
      FileUtils.mkdir_p(File.join(@vault, "templates"))
      File.write(File.join(@vault, "templates/daily.md"), "# {{title}}\n")
      capture_stderr { capture_stdout { described_class.start(["daily"]) } }
      existing = Dir.glob("#{@vault}/daily/*.md").first
      write_config(
        <<~TOML
          vault = "#{@vault}"
          [dailyNote]
          template = "templates/daily.md"
        TOML
      )

      output = capture_stdout { described_class.start(["daily"]) }

      expect(output).to(eq("Recreated: #{existing}\n"))
      expect(File.read(existing)).to(eq("# #{File.basename(existing, ".md")}\n"))
      expect(Dir.glob("#{@vault}/daily/*.backup-*.md")).to(be_empty)
    end

    it "with --force backs up the existing note and recreates it" do
      capture_stderr { capture_stdout { described_class.start(["daily"]) } }
      File.write(Dir.glob("#{@vault}/daily/*.md").first, "user content\n")

      output = nil
      capture_stderr { output = capture_stdout { described_class.start(["daily", "--force"]) } }

      expect(output).to(match(/^Recreated: .* \(backup: .*\.backup-\d{8}-\d{6}\.md\)\n/))
    end

    it "warns and exits 1 when the configured template path is missing" do
      write_config(
        <<~TOML
          vault = "#{@vault}"
          [dailyNote]
          template = "templates/missing.md"
        TOML
      )

      stderr = capture_stderr do
        expect {
          capture_stdout { described_class.start(["daily"]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(match(/Error:.*missing\.md/))
    end

    it "exits 1 naming [dailyNote].template when it is an absolute path" do
      write_config(
        <<~TOML
          vault = "#{@vault}"
          [dailyNote]
          template = "/etc/nob/daily.md"
        TOML
      )

      stderr = capture_stderr do
        expect {
          capture_stdout { described_class.start(["daily"]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(
        include("Error: template path must be relative to the vault: /etc/nob/daily.md ([dailyNote].template)")
      )
      expect(Dir.glob("#{@vault}/daily/*.md")).to(be_empty)
    end

    it "warns to stderr but still creates the note when no daily template is configured" do
      stdout = nil
      stderr = capture_stderr do
        stdout = capture_stdout { described_class.start(["daily"]) }
      end

      expect(stdout).to(match(/^Created: /))
      expect(stderr).to(
        eq("Warning: no daily-note template configured ([dailyNote].template); creating an empty file.\n")
      )
    end

    it "does not warn when a template is configured and exists" do
      template_path = File.join(@vault, "tpl.md")
      File.write(template_path, "# {{title}}\n")
      write_config(
        <<~TOML
          vault = "#{@vault}"
          [dailyNote]
          template = "tpl.md"
        TOML
      )

      stderr = capture_stderr { capture_stdout { described_class.start(["daily"]) } }

      expect(stderr).to(eq(""))
    end

    it "leaves today's note untouched and makes no backup when --force cannot render the template" do
      capture_stderr { capture_stdout { described_class.start(["daily"]) } }
      existing = Dir.glob("#{@vault}/daily/*.md").first
      File.write(existing, "user content\n")
      write_config(
        <<~TOML
          vault = "#{@vault}"
          [dailyNote]
          template = "templates/missing.md"
        TOML
      )

      capture_stderr do
        expect {
          capture_stdout { described_class.start(["daily", "--force"]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(File.read(existing)).to(eq("user content\n"))
      expect(Dir.glob("#{@vault}/daily/*.backup-*.md")).to(be_empty)
    end

    it "exits 1 without writing when basePath escapes the vault" do
      out_dir = File.join(File.dirname(@vault), "out")
      write_config(
        <<~TOML
          vault = "#{@vault}"
          [dailyNote]
          basePath = "../out"
        TOML
      )

      stderr = capture_stderr do
        expect {
          capture_stdout { described_class.start(["daily"]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(match(%r{Error: path escapes the vault: \.\./out/\d{4}-\d{2}-\d{2}\.md}))
      expect(File.exist?(out_dir)).to(be(false))
    end

    it "exits 1 without writing when fileNameFormat escapes the vault" do
      write_config(
        <<~TOML
          vault = "#{@vault}"
          [dailyNote]
          fileNameFormat = "../../%Y-escaped"
        TOML
      )
      escaped_path = File.join(File.dirname(@vault), "#{Time.now.year}-escaped.md")

      stderr = capture_stderr do
        expect {
          capture_stdout { described_class.start(["daily"]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(match(%r{Error: path escapes the vault: daily/\.\./\.\./\d{4}-escaped\.md}))
      expect(File.exist?(escaped_path)).to(be(false))
    end

    context("with a moment fileNameFormat") do
      before { allow(Time).to(receive(:now).and_return(Time.new(2026, 3, 7, 9, 5, 2))) }

      it "creates the note at the path the format builds" do
        write_config(
          <<~TOML
            vault = "#{@vault}"
            [dailyNote]
            basePath = "日記/"
            fileNameFormat = "YYYY/MM/YYYY-MM-DD"
          TOML
        )

        output = nil
        capture_stderr { output = capture_stdout { described_class.start(["daily"]) } }

        expect(output).to(eq("Created: #{File.join(@vault, "日記/2026/03/2026-03-07.md")}\n"))
      end

      it "uses the file name, without the directories in the format, as {{title}}" do
        FileUtils.mkdir_p(File.join(@vault, "templates"))
        File.write(File.join(@vault, "templates/daily.md"), "# {{title}}\n")
        write_config(
          <<~TOML
            vault = "#{@vault}"
            [dailyNote]
            fileNameFormat = "YYYY/MM/YYYY-MM-DD"
            template = "templates/daily.md"
          TOML
        )

        capture_stdout { described_class.start(["daily"]) }

        expect(File.read(File.join(@vault, "daily/2026/03/2026-03-07.md"))).to(eq("# 2026-03-07\n"))
      end

      it "exits 1 naming [dailyNote].fileNameFormat when a token is not supported" do
        write_config(
          <<~TOML
            vault = "#{@vault}"
            [dailyNote]
            fileNameFormat = "YYYY-MM-DD dddd"
          TOML
        )

        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["daily"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(include("Error: unsupported format token: dddd ([dailyNote].fileNameFormat)"))
        expect(Dir.glob("#{@vault}/**/*.md")).to(be_empty)
      end
    end
  end

  describe "#list" do
    context("with the fixture vault") do
      include_context("fixture vault")

      it "prints all notes sorted by relative path" do
        output = capture_stdout { described_class.start(["list"]) }

        expect(output).to(eq(FixtureVault::EXPECTED_NOTES.join("\n") + "\n"))
      end

      it "does not include files under .nob/" do
        output = capture_stdout { described_class.start(["list"]) }

        expect(output).not_to(include(".nob/"))
      end

      it "filters by --prefix" do
        output = capture_stdout { described_class.start(["list", "--prefix", "daily"]) }

        expect(output).to(eq("daily/2026-04-30.md\n"))
      end

      it "filters by --prefix to projects/" do
        output = capture_stdout { described_class.start(["list", "--prefix", "projects"]) }

        expect(output).to(eq("projects/Plan.md\n"))
      end
    end

    context("with an empty vault") do
      include_context("tmp vault")

      it "prints nothing and exits 0 when the vault has no notes" do
        output = capture_stdout { described_class.start(["list"]) }

        expect(output).to(eq(""))
      end
    end

    context("with error conditions") do
      include_context("tmp vault")

      it "warns and exits 1 when the prefix directory does not exist" do
        stderr = capture_stderr do
          expect {
            capture_stdout { described_class.start(["list", "--prefix", "missing"]) }
          }
            .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
        end

        expect(stderr).to(match(/Error.*missing/))
      end
    end
  end

  describe "#links" do
    include_context("tmp vault")

    def touch(relative_path, content = "")
      abs = File.join(@vault, relative_path)
      FileUtils.mkdir_p(File.dirname(abs))
      File.binwrite(abs, content)
    end

    it "lists unresolved and ambiguous links as path:line, sorted by path then line" do
      touch("Plan.md")
      touch("a/Note.md")
      touch("b/Note.md")
      touch("z.md", "[[gone]]\n")
      touch("daily/d.md", "---\ntitle: d\n---\n[[Plan]] [[missing]]\n\n[[Note]] [[missing]]\n")

      output = capture_stdout { described_class.start(["links", "--unresolved"]) }

      expect(output).to(
        eq(
          "daily/d.md:4: [[missing]]\n" \
            "daily/d.md:6: [[Note]] (ambiguous: a/Note.md, b/Note.md)\n" \
            "daily/d.md:6: [[missing]]\n" \
            "z.md:1: [[gone]]\n"
        )
      )
    end

    it "skips a directory whose name ends in .md" do
      touch("archive.md/old.md", "[[gone]]\n")

      expect(capture_stdout { described_class.start(["links", "--unresolved"]) }).to(
        eq("archive.md/old.md:1: [[gone]]\n")
      )
    end

    it "keeps scanning when a file name is not valid UTF-8" do
      touch("bad\xFF.png".b)
      touch("a.md", "[[gone]]\n")

      expect(capture_stdout { described_class.start(["links", "--unresolved"]) }).to(eq("a.md:1: [[gone]]\n"))
    end

    it "ignores links in the frontmatter of a note saved with a BOM" do
      touch("bom.md", "\uFEFF---\nrelated: \"[[gone]]\"\n---\nbody\n")

      expect(capture_stdout { described_class.start(["links", "--unresolved"]) }).to(eq(""))
    end

    it "prints nothing when every link resolves" do
      touch("Plan.md", "[[Plan]]\n")

      expect(capture_stdout { described_class.start(["links", "--unresolved"]) }).to(eq(""))
    end

    it "warns about a note that is not valid UTF-8 and keeps scanning" do
      touch("bad.md", "[[x]] \xFF\n".b)
      touch("good.md", "[[gone]]\n")

      stdout = nil
      stderr = capture_stderr { stdout = capture_stdout { described_class.start(["links", "--unresolved"]) } }

      expect(stderr).to(eq("Warning: skipped bad.md: invalid UTF-8\n"))
      expect(stdout).to(eq("good.md:1: [[gone]]\n"))
    end

    it "exits 1 without --unresolved" do
      stderr = capture_stderr do
        expect {
          capture_stdout { described_class.start(["links"]) }
        }
          .to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(eq("Error: specify --unresolved\n"))
    end
  end

  describe "#resolve" do
    include_context("tmp vault")

    def touch(relative_path, content = "")
      abs = File.join(@vault, relative_path)
      FileUtils.mkdir_p(File.dirname(abs))
      File.write(abs, content)
    end

    def resolve(*args)
      capture_stdout { described_class.start(["resolve", *args]) }
    end

    it "prints the absolute path of the file a link resolves to" do
      touch("projects/Plan.md")

      expect(resolve("[[plan|計画]]")).to(eq("#{File.join(@vault, "projects", "Plan.md")}\n"))
    end

    it "prints every nearest candidate, one per line, when the link is ambiguous" do
      touch("a/Note.md")
      touch("b/Note.md")

      expect(resolve("[[Note]]")).to(eq("#{File.join(@vault, "a", "Note.md")}\n#{File.join(@vault, "b", "Note.md")}\n"))
    end

    it "resolves a link given as bytes, as ARGV is under LANG=C" do
      touch("計画.md")

      expect(resolve("[[計画]]".b)).to(eq("#{File.join(@vault, "計画.md")}\n"))
    end

    it "measures distance from a --from given as bytes, as ARGV is under LANG=C" do
      touch("日記/Plan.md")
      touch("projects/Plan.md")

      expect(resolve("[[Plan]]", "--from", "日記/2026/x.md".b)).to(eq("#{File.join(@vault, "日記", "Plan.md")}\n"))
    end

    it "prints nothing when the link is unresolved" do
      expect(resolve("[[missing]]")).to(eq(""))
    end

    it "measures distance from a vault-relative --from" do
      touch("a/Note.md")
      touch("b/Note.md")

      expect(resolve("[[Note]]", "--from", "a/today.md")).to(eq("#{File.join(@vault, "a", "Note.md")}\n"))
    end

    it "accepts an absolute --from for a file that does not exist yet" do
      touch("a/Note.md")
      touch("b/Note.md")

      expect(resolve("[[Note]]", "--from", File.join(@vault, "b", "new.md"))).to(
        eq("#{File.join(@vault, "b", "Note.md")}\n")
      )
    end

    def expect_error(args, message)
      stderr = capture_stderr do
        expect { resolve(*args) }.to(raise_error(SystemExit) { |e| expect(e.status).to(eq(1)) })
      end

      expect(stderr).to(eq("Error: #{message}\n"))
    end

    it "exits 1 unless the argument is exactly one link" do
      ["Plan", "see [[Plan]] here", "[[a]] [[b]]", "[[#Goals]]"].each do |raw|
        expect_error([raw], "expected a single [[link]]: #{raw}")
      end
    end

    it "exits 1 when --from is a directory" do
      touch("daily/x.md")

      expect_error(["[[x]]", "--from", "daily"], "--from is not a file: daily")
    end

    it "exits 1 when --from ends in a slash, even for a directory that does not exist yet" do
      expect_error(["[[x]]", "--from", "newdir/"], "--from is not a file: newdir/")
    end

    it "exits 1 when --from is outside the vault" do
      expect_error(["[[x]]", "--from", "/etc/hosts"], "--from is outside the vault: /etc/hosts")
    end
  end

  describe "unknown config keys" do
    include_context("tmp vault")

    it "warns about each unknown key, suggesting a close match, and keeps running" do
      write_config(
        <<~TOML
          vault = "#{@vault}"
          editor = "vim"
          [note]
          tempalte = "templates/note.md"
        TOML
      )

      stdout = nil
      stderr = capture_stderr { stdout = capture_stdout { described_class.start(["list"]) } }

      expect(stderr).to(
        eq(
          "Warning: unknown config key editor in #{@config_path}\n" \
            "Warning: unknown config key [note].tempalte in #{@config_path} (did you mean [note].template?)\n"
        )
      )
      expect(stdout).to(eq(""))
    end

    it "prints no warning when every key is known" do
      stderr = capture_stderr { capture_stdout { described_class.start(["list"]) } }

      expect(stderr).to(eq(""))
    end
  end
end
