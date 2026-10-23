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

    context("with size formatting") do
      before do
        @vault = Dir.mktmpdir("nob-vault")
        @cfg_dir = Dir.mktmpdir("nob-cfg")
        config_path = File.join(@cfg_dir, "nob", "config.toml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, "vault = \"#{@vault}\"\n")
        allow(Nob::Config).to(receive(:default_path).and_return(config_path))
      end

      after do
        FileUtils.remove_entry(@vault) if @vault
        FileUtils.remove_entry(@cfg_dir) if @cfg_dir
      end

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
      before do
        @vault = Dir.mktmpdir("nob-vault")
        @cfg_dir = Dir.mktmpdir("nob-cfg")
        config_path = File.join(@cfg_dir, "nob", "config.toml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, "vault = \"#{@vault}\"\n")
        allow(Nob::Config).to(receive(:default_path).and_return(config_path))
      end

      after do
        FileUtils.remove_entry(@vault) if @vault
        FileUtils.remove_entry(@cfg_dir) if @cfg_dir
      end

      def touch(relative_path, content = "")
        abs = File.join(@vault, relative_path)
        FileUtils.mkdir_p(File.dirname(abs))
        File.write(abs, content)
        abs
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
    before do
      @vault = Dir.mktmpdir("nob-vault")
      @cfg_dir = Dir.mktmpdir("nob-cfg")
      @config_path = File.join(@cfg_dir, "nob", "config.toml")
      FileUtils.mkdir_p(File.dirname(@config_path))
      File.write(@config_path, "vault = \"#{@vault}\"\n")
      allow(Nob::Config).to(receive(:default_path).and_return(@config_path))
    end

    after do
      FileUtils.remove_entry(@vault) if @vault
      FileUtils.remove_entry(@cfg_dir) if @cfg_dir
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
        File.write(
          @config_path,
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
    before do
      @vault = Dir.mktmpdir("nob-vault")
      @cfg_dir = Dir.mktmpdir("nob-cfg")
      @config_path = File.join(@cfg_dir, "nob", "config.toml")
      FileUtils.mkdir_p(File.dirname(@config_path))
      File.write(@config_path, "vault = \"#{@vault}\"\n")
      allow(Nob::Config).to(receive(:default_path).and_return(@config_path))
    end

    after do
      FileUtils.remove_entry(@vault) if @vault
      FileUtils.remove_entry(@cfg_dir) if @cfg_dir
    end

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

    it "with --force backs up the existing note and recreates it" do
      capture_stderr { capture_stdout { described_class.start(["daily"]) } }
      File.write(Dir.glob("#{@vault}/daily/*.md").first, "user content\n")

      output = nil
      capture_stderr { output = capture_stdout { described_class.start(["daily", "--force"]) } }

      expect(output).to(match(/^Recreated: .* \(backup: .*\.backup-\d{8}-\d{6}\.md\)\n/))
    end

    it "warns and exits 1 when the configured template path is missing" do
      File.write(
        @config_path,
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

    it "warns to stderr but still creates the note when no daily template is configured" do
      stdout = nil
      stderr = capture_stderr do
        stdout = capture_stdout { described_class.start(["daily"]) }
      end

      expect(stdout).to(match(/^Created: /))
      expect(stderr).to(match(/^Warning: no daily-note template configured/))
    end

    it "does not warn when a template is configured and exists" do
      template_path = File.join(@vault, "tpl.md")
      File.write(template_path, "# {{title}}\n")
      File.write(
        @config_path,
        <<~TOML
          vault = "#{@vault}"
          [dailyNote]
          template = "tpl.md"
        TOML
      )

      stderr = capture_stderr { capture_stdout { described_class.start(["daily"]) } }

      expect(stderr).to(eq(""))
    end

    it "exits 1 without writing when basePath escapes the vault" do
      out_dir = File.join(File.dirname(@vault), "out")
      File.write(
        @config_path,
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
      File.write(
        @config_path,
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
      before do
        @empty_vault = Dir.mktmpdir("nob-empty-vault")
        cfg_dir = Dir.mktmpdir("nob-cfg")
        config_path = File.join(cfg_dir, "nob", "config.toml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, "vault = \"#{@empty_vault}\"\n")
        allow(Nob::Config).to(receive(:default_path).and_return(config_path))
        @cfg_dir = cfg_dir
      end

      after do
        FileUtils.remove_entry(@empty_vault)
        FileUtils.remove_entry(@cfg_dir)
      end

      it "prints nothing and exits 0 when the vault has no notes" do
        output = capture_stdout { described_class.start(["list"]) }

        expect(output).to(eq(""))
      end
    end

    context("with error conditions") do
      it "warns and exits 1 when the prefix directory does not exist" do
        Dir.mktmpdir("nob-vault") do |vault|
          Dir.mktmpdir("nob-cfg") do |cfg_dir|
            config_path = File.join(cfg_dir, "nob", "config.toml")
            FileUtils.mkdir_p(File.dirname(config_path))
            File.write(config_path, "vault = \"#{vault}\"\n")
            allow(Nob::Config).to(receive(:default_path).and_return(config_path))

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
    end
  end
end
