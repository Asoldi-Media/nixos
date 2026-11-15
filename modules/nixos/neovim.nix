# Feature module: system-wide Neovim with sensible defaults, fuzzy finder,
# syntax highlighting, and Nix LSP.
# Published as flake.nixosModules.neovim
{
  flake.nixosModules.neovim =
    { pkgs, ... }:
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;

        configure = {
          packages.plugins.start = with pkgs.vimPlugins; [
            telescope-nvim # fuzzy finder; needs plenary
            plenary-nvim
            nvim-treesitter.withAllGrammars
            nvim-lspconfig
            gitsigns-nvim
          ];

          customRC = ''
            lua << EOF
            local o = vim.opt
            vim.g.mapleader = " "

            o.number = true
            o.relativenumber = true
            o.mouse = "a"
            o.clipboard = "unnamedplus"   -- needs wl-clipboard or xclip at runtime
            o.ignorecase = true
            o.smartcase = true
            o.undofile = true
            o.signcolumn = "yes"
            o.cursorline = true
            o.scrolloff = 8
            o.termguicolors = true
            o.expandtab = true
            o.shiftwidth = 2
            o.tabstop = 2
            o.splitright = true
            o.splitbelow = true
            o.updatetime = 250

            local map = vim.keymap.set
            map("n", "<Esc>", "<cmd>nohlsearch<cr>")
            map("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
            map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>")
            map("n", "<leader>fb", "<cmd>Telescope buffers<cr>")
            map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>")
            map("n", "<leader>e", vim.diagnostic.open_float)

            -- Tree-sitter highlighting (grammars come from Nix).
            vim.api.nvim_create_autocmd("FileType", {
              callback = function() pcall(vim.treesitter.start) end,
            })

            require("gitsigns").setup()

            -- LSP: nil for Nix. Defaults give gd, K, grn, gra, grr, <C-s>.
            vim.lsp.config("nil_ls", {})
            vim.lsp.enable("nil_ls")
            vim.api.nvim_create_autocmd("LspAttach", {
              callback = function(ev)
                vim.lsp.completion.enable(true, ev.data.client_id, ev.buf, { autotrigger = true })
              end,
            })
            EOF
          '';
        };
      };

      # Tools the editor calls at runtime.
      environment.systemPackages = with pkgs; [
        nil # Nix LSP
        nixfmt # Nix formatter
        ripgrep # Telescope live_grep
        fd # Telescope find_files
        wl-clipboard # system clipboard on Wayland (COSMIC)
      ];
    };
}
