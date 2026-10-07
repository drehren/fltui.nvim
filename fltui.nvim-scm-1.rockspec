rockspec_format = '3.0'
package = 'fltui.nvim'
version = 'scm-1'
description = {
    homepage = 'https://github.com/drehren/fltui.nvim',
    labels = { 'neovim' },

    license = 'MIT',
}
source = {
    url = 'git://github.com/drehren/fltui.nvim',
}
dependencies = {
    'lua >=5.1, < 5.4',
}
test_dependencies = {
    'nlua',
}
build = {
    type = 'builtin',
    copy_directories = {
        'doc',
        'plugin',
    },
}
