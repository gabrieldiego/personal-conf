
"""""""""""""""""""""""""""""""""""""""""
" Usefull options for everybody
"""""""""""""""""""""""""""""""""""""""""


" Normally we use vim-extensions. If you want true vi-compatibility
" remove change the following statements
set nocompatible        " Use Vim defaults (much better!)
set backspace=2         " allow backspacing over everything in insert mode

" Now we set some defaults for the editor
set autoindent          " always set autoindenting on
set viminfo='20,\"50    " read/write a .viminfo file, don't store more than
                        " 50 lines of registers
set history=50          " keep 50 lines of command line history
set ruler               " show the cursor position all the time

set showcmd             " Show (partial) command in status line.
set showmatch           " Show matching brackets.
set matchpairs+=<:>
set incsearch           " Incremental search
set exrc
set secure
set clipboard=


if has("syntax")
  syntax on             " Default to no syntax highlightning
endif

if &term =~ "xterm"
  set title titlestring=%<%F%=%l/%L-%P titlelen=70
endif

" Suffixes that get lower priority when doing tab completion for filenames.
" These are files we are not likely to want to edit or read.
set suffixes=.bak,~,.swp,.o,.info,.aux,.log,.dvi,.bbl,.blg,.brf,.cb,.ind,.idx,.ilg,.inx,.out,.toc,.d

" We know xterm-debian is a color terminal
if &term =~ "xterm-debian" || &term =~ "xterm-xfree86"
  set t_Co=16
  set t_Sf=[3%dm
  set t_Sb=[4%dm
endif


" source /utils/unix_share/vim/runtime.vim
set runtimepath-=~/.vim/after
set runtimepath+=~/.vim/after

"""""""""""""""""""""""""""""""""""""""""
" Options depending of user setup
"""""""""""""""""""""""""""""""""""""""""

" If using a dark background within the editing area and syntax highlighting
set background=dark

" Uncomment this to use the mouse in an xterm
set mouse=a

" comment this if you want vim to save backup file
set nobackup            " Don't keep a backup file

"set ignorecase          " Do case insensitive matching
"set autowrite           " Automatically save before commands like :next and :make

set textwidth=0         " Don't wrap words by default

set hlsearch
" set cursorline        " Show cursor position

set wildmode=longest,list,full
set wildmenu                    " command-line completion in an enhanced mode

"""""""""""""""""""""""""""""""""""""""""
" Indentation stuff
"""""""""""""""""""""""""""""""""""""""""

filetype indent on
filetype plugin on

autocmd BufEnter * let @m=expand('%:p')

set shiftwidth=2
set expandtab


"default asm is spasm
let g:asmsyntax="spasm"

"""""""""""""""""""""""""""""""""""""""""
set tags=tags;

"""" use ; as leader key (instead of backslash)
let mapleader = ";"
" map ; :

" auto reload
"auto reload vimrc if it changes
augroup myvimrc
    au!
        au BufWritePost .vimrc,_vimrc,vimrc,.gvimrc,_gvimrc,gvimrc so $MYVIMRC
        if has('gui_running') | so $MYGVIMRC | endif
        augroup END

""""" Let all buffers in memory. This allow to :
"       - have a separate history for each buffer
"       - switch buffer without saving
set hidden
set list
set listchars=nbsp:¬

" associate *.spy with conf syntax highlight
au BufRead,BufNewFile *.spy set filetype=conf

" Set clipboard by default "
set clipboard=unnamedplus


autocmd BufNewFile,BufReadPost *.asm set filetype=cpp
