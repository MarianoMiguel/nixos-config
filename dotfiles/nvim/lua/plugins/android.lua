return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- JetBrains' official Kotlin LSP imports Gradle and Android Gradle
        -- Plugin projects and is provided declaratively as `kotlin-lsp`.
        kotlin_lsp = {
          single_file_support = false,
        },
        jdtls = {},
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        java = { "google-java-format" },
        kotlin = { "ktlint" },
      },
    },
  },
}
