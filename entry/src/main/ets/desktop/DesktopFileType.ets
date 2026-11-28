/*
 * Filename rules and icon selection from the bundled @deepseek-ai/dsh-client-ui-primitives
 * FileTypeIcon and CodeFileIcon (DSH 0.2.3-alpha.2, Copyright (c) 2026 DeepSeek, MIT).
 * Attachments pass a filename without a project context.
 */

const FILENAME_TYPES: Map<string, string> = new Map<string, string>([
  ['.bash_profile', 'shell'],
  ['.bashrc', 'shell'],
  ['.env', 'env'],
  ['.gitattributes', 'git'],
  ['.gitconfig', 'git'],
  ['.gitignore', 'git'],
  ['.gitmodules', 'git'],
  ['.mailmap', 'git'],
  ['.profile', 'shell'],
  ['.zprofile', 'shell'],
  ['.zshrc', 'shell'],
  ['bsdmakefile', 'makefile'],
  ['changelog', 'markdown'],
  ['cmakelists.txt', 'cmake'],
  ['commit_editmsg', 'git'],
  ['compose.yaml', 'docker'],
  ['compose.yml', 'docker'],
  ['contributing', 'markdown'],
  ['docker-compose.yaml', 'docker'],
  ['docker-compose.yml', 'docker'],
  ['dockerfile', 'docker'],
  ['gemfile', 'ruby'],
  ['gnumakefile', 'makefile'],
  ['guardfile', 'ruby'],
  ['makefile', 'makefile'],
  ['npm-shrinkwrap.json', 'node'],
  ['package-lock.json', 'node'],
  ['package.json', 'node'],
  ['podfile', 'ruby'],
  ['rakefile', 'ruby'],
  ['readme', 'markdown']
]);

const EXTENSION_TYPES: Map<string, string> = new Map<string, string>([
  ['astro', 'code'],
  ['avi', 'video'],
  ['avif', 'image'],
  ['bash', 'shell'],
  ['bat', 'code'],
  ['bmp', 'image'],
  ['c', 'c'],
  ['c++', 'cpp'],
  ['cc', 'cpp'],
  ['cfg', 'ini'],
  ['cjs', 'javascript'],
  ['clj', 'clojure'],
  ['cljc', 'clojure'],
  ['cljs', 'clojure'],
  ['cmake', 'cmake'],
  ['cmd', 'code'],
  ['cpp', 'cpp'],
  ['cs', 'csharp'],
  ['csh', 'shell'],
  ['css', 'css'],
  ['csv', 'excel'],
  ['csx', 'csharp'],
  ['cts', 'typescript'],
  ['cxx', 'cpp'],
  ['dart', 'dart'],
  ['doc', 'word'],
  ['docx', 'word'],
  ['dtd', 'xml'],
  ['edn', 'clojure'],
  ['env', 'env'],
  ['erl', 'erlang'],
  ['es6', 'javascript'],
  ['escript', 'erlang'],
  ['ex', 'elixir'],
  ['exs', 'elixir'],
  ['fish', 'shell'],
  ['fods', 'excel'],
  ['gemspec', 'ruby'],
  ['gif', 'image'],
  ['go', 'go'],
  ['gql', 'graphql'],
  ['graphql', 'graphql'],
  ['h', 'c'],
  ['h++', 'cpp'],
  ['heic', 'image'],
  ['heif', 'image'],
  ['hh', 'cpp'],
  ['hpp', 'cpp'],
  ['hrl', 'erlang'],
  ['hs', 'haskell'],
  ['htm', 'html'],
  ['html', 'html'],
  ['hxx', 'cpp'],
  ['ico', 'image'],
  ['ini', 'ini'],
  ['ipp', 'cpp'],
  ['java', 'java'],
  ['jpeg', 'image'],
  ['jpg', 'image'],
  ['js', 'javascript'],
  ['json', 'json'],
  ['json5', 'json'],
  ['jsonc', 'json'],
  ['jsx', 'react'],
  ['key', 'ppt'],
  ['ksh', 'shell'],
  ['kt', 'kotlin'],
  ['kts', 'kotlin'],
  ['less', 'code'],
  ['lhs', 'haskell'],
  ['lua', 'lua'],
  ['m', 'objective-c'],
  ['m4v', 'video'],
  ['mak', 'makefile'],
  ['markdown', 'markdown'],
  ['md', 'markdown'],
  ['mdx', 'markdown'],
  ['mjs', 'javascript'],
  ['mk', 'makefile'],
  ['mkv', 'video'],
  ['mm', 'objective-c'],
  ['mov', 'video'],
  ['mp4', 'video'],
  ['mpeg', 'video'],
  ['mpg', 'video'],
  ['mts', 'typescript'],
  ['node', 'node'],
  ['numbers', 'excel'],
  ['ods', 'excel'],
  ['odt', 'word'],
  ['ots', 'excel'],
  ['pages', 'word'],
  ['pch', 'objective-c'],
  ['pdf', 'pdf'],
  ['php', 'php'],
  ['php3', 'php'],
  ['php4', 'php'],
  ['php5', 'php'],
  ['phps', 'php'],
  ['phtml', 'php'],
  ['pl', 'perl'],
  ['plist', 'xml'],
  ['pm', 'perl'],
  ['png', 'image'],
  ['pod', 'perl'],
  ['ppt', 'ppt'],
  ['pptx', 'ppt'],
  ['proto', 'protobuf'],
  ['ps1', 'powershell'],
  ['psd1', 'powershell'],
  ['psm1', 'powershell'],
  ['py', 'python'],
  ['pyi', 'python'],
  ['pyw', 'python'],
  ['pyx', 'python'],
  ['r', 'r'],
  ['rake', 'ruby'],
  ['rb', 'ruby'],
  ['rmd', 'r'],
  ['rs', 'rust'],
  ['rtf', 'word'],
  ['sass', 'code'],
  ['sc', 'scala'],
  ['scala', 'scala'],
  ['scss', 'code'],
  ['sh', 'shell'],
  ['sol', 'solidity'],
  ['sql', 'sql'],
  ['svelte', 'svelte'],
  ['svg', 'image'],
  ['swift', 'swift'],
  ['t', 'perl'],
  ['tcsh', 'shell'],
  ['tif', 'image'],
  ['tiff', 'image'],
  ['toml', 'toml'],
  ['tpp', 'cpp'],
  ['ts', 'typescript'],
  ['tsv', 'excel'],
  ['tsx', 'react'],
  ['vue', 'vue'],
  ['wasm', 'wasm'],
  ['wast', 'wasm'],
  ['wat', 'wasm'],
  ['webm', 'video'],
  ['webp', 'image'],
  ['xls', 'excel'],
  ['xlsb', 'excel'],
  ['xlsm', 'excel'],
  ['xlsx', 'excel'],
  ['xlt', 'excel'],
  ['xltm', 'excel'],
  ['xltx', 'excel'],
  ['xml', 'xml'],
  ['xsd', 'xml'],
  ['xsl', 'xml'],
  ['xslt', 'xml'],
  ['yaml', 'yaml'],
  ['yml', 'yaml'],
  ['zig', 'zig'],
  ['zsh', 'shell']
]);

const ANGULAR_SUFFIXES: string[] = [
  '.component.ts', '.component.html', '.directive.ts', '.service.ts',
  '.module.ts', '.pipe.ts', '.guard.ts', '.interceptor.ts'
];

export function desktopFileType(path: string): string {
  const name = path.slice(Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\')) + 1).toLowerCase();
  const exact = FILENAME_TYPES.get(name);
  if (exact !== undefined) { return exact; }
  if (name.startsWith('dockerfile.')) { return 'docker'; }
  if (name.startsWith('.env.')) { return 'env'; }
  if (ANGULAR_SUFFIXES.some((suffix: string): boolean => name.endsWith(suffix))) { return 'angular'; }
  if (name.endsWith('.dockerfile')) { return 'docker'; }
  const dot = name.lastIndexOf('.');
  return dot < 0 ? 'other' : (EXTENSION_TYPES.get(name.slice(dot + 1)) ?? 'other');
}

export function desktopFileTypeIcon(path: string): Resource {
  switch (desktopFileType(path)) {
    case 'angular': return $r('app.media.dsh_file_type_angular');
    case 'c': return $r('app.media.dsh_file_type_c');
    case 'clojure': return $r('app.media.dsh_file_type_clojure');
    case 'cmake': return $r('app.media.dsh_file_type_cmake');
    case 'code': return $r('app.media.dsh_file_type_code');
    case 'cpp': return $r('app.media.dsh_file_type_cpp');
    case 'csharp': return $r('app.media.dsh_file_type_csharp');
    case 'css': return $r('app.media.dsh_file_type_css');
    case 'dart': return $r('app.media.dsh_file_type_dart');
    case 'docker': return $r('app.media.dsh_file_type_docker');
    case 'elixir': return $r('app.media.dsh_file_type_elixir');
    case 'env': return $r('app.media.dsh_file_type_env');
    case 'erlang': return $r('app.media.dsh_file_type_erlang');
    case 'excel': return $r('app.media.dsh_file_type_excel');
    case 'git': return $r('app.media.dsh_file_type_git');
    case 'go': return $r('app.media.dsh_file_type_go');
    case 'graphql': return $r('app.media.dsh_file_type_graphql');
    case 'haskell': return $r('app.media.dsh_file_type_haskell');
    case 'html': return $r('app.media.dsh_file_type_html');
    case 'image': return $r('app.media.dsh_file_type_image');
    case 'ini': return $r('app.media.dsh_file_type_ini');
    case 'java': return $r('app.media.dsh_file_type_java');
    case 'javascript': return $r('app.media.dsh_file_type_javascript');
    case 'json': return $r('app.media.dsh_file_type_json');
    case 'kotlin': return $r('app.media.dsh_file_type_kotlin');
    case 'lua': return $r('app.media.dsh_file_type_lua');
    case 'makefile': return $r('app.media.dsh_file_type_makefile');
    case 'markdown': return $r('app.media.dsh_file_type_markdown');
    case 'node': return $r('app.media.dsh_file_type_node');
    case 'objective-c': return $r('app.media.dsh_file_type_objective_c');
    case 'pdf': return $r('app.media.dsh_file_type_pdf');
    case 'perl': return $r('app.media.dsh_file_type_perl');
    case 'php': return $r('app.media.dsh_file_type_php');
    case 'powershell': return $r('app.media.dsh_file_type_powershell');
    case 'ppt': return $r('app.media.dsh_file_type_ppt');
    case 'protobuf': return $r('app.media.dsh_file_type_protobuf');
    case 'python': return $r('app.media.dsh_file_type_python');
    case 'r': return $r('app.media.dsh_file_type_r');
    case 'react': return $r('app.media.dsh_file_type_react');
    case 'ruby': return $r('app.media.dsh_file_type_ruby');
    case 'rust': return $r('app.media.dsh_file_type_rust');
    case 'scala': return $r('app.media.dsh_file_type_scala');
    case 'shell': return $r('app.media.dsh_file_type_shell');
    case 'solidity': return $r('app.media.dsh_file_type_solidity');
    case 'sql': return $r('app.media.dsh_file_type_sql');
    case 'svelte': return $r('app.media.dsh_file_type_svelte');
    case 'swift': return $r('app.media.dsh_file_type_swift');
    case 'toml': return $r('app.media.dsh_file_type_toml');
    case 'typescript': return $r('app.media.dsh_file_type_typescript');
    case 'video': return $r('app.media.dsh_file_type_video');
    case 'vue': return $r('app.media.dsh_file_type_vue');
    case 'wasm': return $r('app.media.dsh_file_type_wasm');
    case 'word': return $r('app.media.dsh_file_type_word');
    case 'xml': return $r('app.media.dsh_file_type_xml');
    case 'yaml': return $r('app.media.dsh_file_type_yaml');
    case 'zig': return $r('app.media.dsh_file_type_zig');
    default: return $r('app.media.dsh_file_type_other');
  }
}
