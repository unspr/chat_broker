directory "bin"

task :dependency do
  url = "https://raw.githubusercontent.com/IndySockets/OpenSSL-Binaries/master/openssl-3_x/openssl-3.3.2-win64.zip"
  zip_name = "openssl.zip"
  sh "curl -o #{zip_name} #{url}"
  sh "powershell -Command \"& { Add-Type -A 'System.IO.Compression.FileSystem'; [IO.Compression.ZipFile]::OpenRead('#{zip_name}').Entries | Where-Object { $_.Name -match 'lib(ssl|crypto)-3-x64\\.dll' } | ForEach-Object { [IO.Compression.ZipFileExtensions]::ExtractToFile($_, $_.Name, $true) } }\""
  sh "mv libssl-3-x64.dll bin/"
  sh "mv libcrypto-3-x64.dll bin/"
  rm_f zip_name
  
  sh "git submodule update --init --recursive"
  sh "lazbuild --add-package-link external/html_viewer/package/FrameViewer09.lpk"
  sh "lazbuild --add-package-link external/synapse/laz_synapse.lpk"
  sh "lazbuild --add-package-link external/fpc-markdown/fpc_markdown.lpk"
end