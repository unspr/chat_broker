file "libssl-1_1-x64.dll" do
  sh "curl -o libssl-1_1-x64.dll https://gitlab.com/freepascal.org/lazarus/binaries/-/raw/main/x86_64-win64/openssl/libssl-1_1-x64.dll"
end

file "libcrypto-1_1-x64.dll" do
  sh "curl -o libcrypto-1_1-x64.dll https://gitlab.com/freepascal.org/lazarus/binaries/-/raw/main/x86_64-win64/openssl/libcrypto-1_1-x64.dll"
end

task :install => ["libssl-1_1-x64.dll", "libcrypto-1_1-x64.dll"] do end
