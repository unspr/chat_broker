directory "bin"

file "bin/ChatRouter.exe" => "bin" do
  sh "curl -o bin/ChatRouter.exe https://github.com/unspr/chat-router/releases/download/latest/ChatRouter.exe"
end

task :install => ["bin/ChatRouter.exe"] do
  sh "git submodule update --init --recursive"
  sh "lazbuild --add-package-link external/html_viewer/package/FrameViewer09.lpk"
  sh "lazbuild --add-package-link external/fpc-markdown/fpc_markdown.lpk"
end