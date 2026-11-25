# An example cask for a private tap, downloading with the GitHub CLI
# (lib/private_github_release.rb beside it). `make bump-cask` rewrites the
# `version` and `sha256` lines, so keep them in this form.
require_relative "../lib/private_github_release"

cask "myapp" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/example/myapp/releases/download/v#{version}/MyApp-#{version}-macos.zip",
      using: PrivateGitHubReleaseDownloadStrategy
  name "MyApp"
  desc "What it does, in a few words"
  homepage "https://github.com/example/myapp"

  depends_on macos: :tahoe

  app "MyApp.app"

  uninstall quit: "com.example.myapp"
end
