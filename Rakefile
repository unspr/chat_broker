directory "bin"

file "bin/libssl-1_1-x64.dll" => "bin" do
  sh "curl -o bin/libssl-1_1-x64.dll https://gitlab.com/freepascal.org/lazarus/binaries/-/raw/main/x86_64-win64/openssl/libssl-1_1-x64.dll"
end

file "bin/libcrypto-1_1-x64.dll" => "bin" do
  sh "curl -o bin/libcrypto-1_1-x64.dll https://gitlab.com/freepascal.org/lazarus/binaries/-/raw/main/x86_64-win64/openssl/libcrypto-1_1-x64.dll"
end

task :install => ["bin/libssl-1_1-x64.dll", "bin/libcrypto-1_1-x64.dll"]
