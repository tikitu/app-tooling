# typed: false
# frozen_string_literal: true

# Downloads an asset of a release in a private GitHub repository with the
# GitHub CLI, which brings its own login (`gh auth login`).
#
# Why not a plain `url` with an `Authorization` header: the header, token
# and all, becomes part of the cask, and `brew info --json` prints it.
# Here the token never passes through Homebrew: not in the cask, not in its
# output, not in any command line.
#
# The `url` is the asset's ordinary download address,
# https://github.com/<owner>/<repo>/releases/download/<tag>/<file>, which
# is where the tag and file name are read from.
class PrivateGitHubReleaseDownloadStrategy < AbstractFileDownloadStrategy
  URL_PATTERN = %r{\Ahttps://github\.com/(?<repo>[^/]+/[^/]+)/releases/download/(?<tag>[^/]+)/(?<file>[^/]+)\z}

  def fetch(timeout: nil)
    if cached_location.exist?
      puts "Already downloaded: #{cached_location}"
    else
      parts = URL_PATTERN.match(url)
      raise CannotDownload, "not a GitHub release download address: #{url}" unless parts

      # Whether to have gh, and whether to log it in, is each person's
      # choice: say what is needed and the other way to get it, but never
      # suggest installing gh or `gh auth login` (gh's own error would).
      gh = which("gh", ORIGINAL_PATHS)
      raise CannotDownload, unavailable(parts, "gh is not installed here.") unless gh

      ohai "Downloading #{url} (with gh)"
      rm_f temporary_path
      temporary_path.dirname.mkpath
      result = system_command gh, args: ["release", "download", parts[:tag], "--repo", parts[:repo],
                                         "--pattern", parts[:file], "--output", temporary_path.to_s],
                                  print_stderr: false
      unless result.success?
        rm_f temporary_path
        reason = "gh could not download it: not logged in, or without access to #{parts[:repo]}."
        reason += "\n\ngh said:\n#{result.stderr.strip}" if verbose?
        raise CannotDownload, unavailable(parts, reason)
      end
      cached_location.dirname.mkpath
      temporary_path.rename(cached_location)
    end
    create_symlink_to_cached_download(cached_location)
  end

  # What went wrong, and the plain download, which needs only a browser
  # logged in to GitHub.
  def unavailable(parts, reason)
    <<~EOS
      #{name} is in a private GitHub repository, so this cask downloads it
      with the GitHub CLI (gh), logged in with access to #{parts[:repo]}.
      #{reason}

      Instead, download it from https://github.com/#{parts[:repo]}/releases
      and follow "Installing it" in the README there.
    EOS
  end

  class CannotDownload < RuntimeError; end

  def total_size
    nil
  end

  def clear_cache
    super
    rm_rf temporary_path
  end
end
