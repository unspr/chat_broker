unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Menus, config,
  gemini, IniFiles, HtmlView, ExtCtrls, MarkdownProcessor, MarkdownUtils, ComCtrls;

type

  { TMainForm }

  TMainForm = class(TForm)
    NewConversation: TButton;
    Edit1: TEdit;
    SendBtn: TButton;
    ConfigBtn: TButton;
    FMessageContainer: TFlowPanel;
    ScrollBox: TScrollBox;
    procedure SendBtnClick(Sender: TObject);
    procedure ConfigBtnClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure HtmlViewer1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure NewConversationClick(Sender: TObject);
  private
    FGeminiAPI: TGeminiAPI;
    md : TMarkdownProcessor;
    FCurrentAIViewer: THtmlViewer;  // 当前正在接收 AI 回复的 HtmlViewer
    FAIContentBuffer: TStringList;   // AI 回复内容缓冲区
    FIsReceivingAI: Boolean;
    FMessageCount: Integer;          // 消息计数器
    procedure CreateUserMessage(const AText: string);
    function CreateAIViewer: THtmlViewer;
    procedure AppendToAIViewer(const AText: string);
    function LoadConfig: TStringList;
    procedure OnSSEStart(Sender: TObject);
    procedure OnSSEData(Sender: TObject; const AText: string; IsDone: Boolean);
    procedure OnSSEError(Sender: TObject; const AError: string);
  public

  end;
const
  EM_SCROLLCARET = $00B7;
var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ TMainForm }

function EscapeHTML(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&#39;', [rfReplaceAll]);
end;

function GetCSSStyles: string;
begin
  Result := 
    'body { font-family: Arial, sans-serif; margin: 0; padding: 8px; }' + sLineBreak +
    '.user-msg { margin: 5px 0; padding: 8px; background-color: #e3f2fd; border-radius: 5px; }' + sLineBreak +
    '.ai-msg { margin: 5px 0; padding: 8px; background-color: #f5f5f5; border-radius: 5px; }';
end;

procedure TMainForm.CreateUserMessage(const AText: string);
var
  Viewer: THtmlViewer;
  HTML: string;
begin
  // 创建 HtmlViewer
  Viewer := THtmlViewer.Create(FMessageContainer);
  Viewer.Parent := FMessageContainer;
  Viewer.Width := FMessageContainer.ClientWidth;
  Viewer.Height := 60;
  Viewer.OnKeyDown := @HtmlViewer1KeyDown;

  // 生成用户消息 HTML
  HTML := '<!DOCTYPE html><html><head>' +
          '<meta charset="UTF-8">' +
          '<style>' + GetCSSStyles + '</style>' +
          '</head><body>' +
          '<div class="user-msg"><strong>me:</strong> ' + EscapeHTML(AText) + '</div>' +
          '</body></html>';
  
  Viewer.LoadFromString(HTML);
  
  // 滚动到底部
  FMessageContainer.ScrollBy(0, FMessageContainer.Height);
end;

function TMainForm.CreateAIViewer: THtmlViewer;
begin
  // 创建 HtmlViewer
  Result := THtmlViewer.Create(FMessageContainer);
  Result.Parent := FMessageContainer;
  Result.Width := FMessageContainer.ClientWidth;
  Result.Height := 60;
  Result.OnKeyDown := @HtmlViewer1KeyDown;

  FAIContentBuffer.Clear;
  FAIContentBuffer.Add('AI: ');

  // 滚动到底部
  FMessageContainer.ScrollBy(0, FMessageContainer.Height);
end;

procedure TMainForm.AppendToAIViewer(const AText: string);
var
  content: string;
begin
  if not Assigned(FCurrentAIViewer) then Exit;
  
  // 追加内容到缓冲区
  FAIContentBuffer.Add(AText);
  content := UTF8String(FAIContentBuffer.Text);
  FCurrentAIViewer.LoadFromString(md.process(content));
  if content.Length > 300 then
  begin
    FCurrentAIViewer.Height := 400;
  end;

  // 滚动到底部
  FMessageContainer.ScrollBy(0, FMessageContainer.Height);
end;

function TMainForm.LoadConfig: TStringList;
var
  Ini: TIniFile;
  IniFileName: string;
begin
  Result := TStringList.Create;
  IniFileName := ExtractFilePath(Application.ExeName) + 'config.ini';
  Ini := TIniFile.Create(IniFileName);
  try
    Result.Add(Ini.ReadString('AIConfig', 'URL', ''));
    Result.Add(Ini.ReadString('AIConfig', 'Token', ''));
    Result.Add(Ini.ReadString('Proxy', 'Host', ''));
    Result.Add(Ini.ReadString('Proxy', 'Port', '0'));
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.OnSSEStart(Sender: TObject);
begin
  // 开始接收 AI 回复，创建新的 AI Viewer
  FCurrentAIViewer := CreateAIViewer;
  FIsReceivingAI := True;
  SendBtn.Enabled := False; // Disable SendBtn when SSE starts
end;

procedure TMainForm.OnSSEData(Sender: TObject; const AText: string; IsDone: Boolean);
begin
  if AText <> '' then
  begin
    AppendToAIViewer(AText);
  end;
  
  if IsDone then
  begin
    if FIsReceivingAI and Assigned(FCurrentAIViewer) then
    begin
      FIsReceivingAI := False;
      FCurrentAIViewer := nil;
    end;
    SendBtn.Enabled := True; // Enable SendBtn when SSE is done
  end;
end;

procedure TMainForm.OnSSEError(Sender: TObject; const AError: string);
begin
  if FIsReceivingAI then
  begin
    AppendToAIViewer('Error: ' + AError);
    FIsReceivingAI := False;
    FCurrentAIViewer := nil;
  end;
  SendBtn.Enabled := True; // Enable SendBtn on error
end;

procedure TMainForm.SendBtnClick(Sender: TObject);
var
  Config: TStringList;
  URL, Token: string;
  Prompt: string;
  ProxyHost: string;
  ProxyPort: Word;
begin
  if Trim(Edit1.Text) = '' then Exit;

  Prompt := Edit1.Text;
  
  // 添加用户消息
  CreateUserMessage(Prompt);
  
  Edit1.Clear;

  Config := LoadConfig;
  try
    if Config.Count >= 2 then
    begin
      URL := Config[0];
      Token := Config[1];
      ProxyHost := Config[2];
      if Config[3] <> '' then
      begin
         ProxyPort := StrToInt(Config[3]);
      end;

      if Trim(URL) = '' then
      begin
        if Assigned(FCurrentAIViewer) then
          AppendToAIViewer('Error: URL 未配置');
        Exit;
      end;

      if Trim(Token) = '' then
      begin
        if Assigned(FCurrentAIViewer) then
          AppendToAIViewer('Error: Token 未配置');
        Exit;
      end;

      // 只在第一次或配置变化时创建/重建 TGeminiAPI 实例
      if not Assigned(FGeminiAPI) then
      begin
        FGeminiAPI := TGeminiAPI.Create(URL, Token, ProxyHost, ProxyPort);
        FGeminiAPI.OnStart := @OnSSEStart;
        FGeminiAPI.OnData := @OnSSEData;
        FGeminiAPI.OnError := @OnSSEError;
      end;

      if FGeminiAPI.IsBusy then
      begin
        if Assigned(FCurrentAIViewer) then
          AppendToAIViewer('Error: 正在等待上一个请求仍在进行中');
        Exit;
      end;

      FGeminiAPI.SendPrompt(Prompt);
    end
    else
    begin
      if Assigned(FCurrentAIViewer) then
        AppendToAIViewer('Error: 配置未正确加载');
    end;
  finally
    Config.Free;
  end;
end;

procedure TMainForm.ConfigBtnClick(Sender: TObject);
begin
  if CfgForm= nil then
    CfgForm := TCfgForm.Create(Application);
  try
    CfgForm.ShowModal;
  finally
    CfgForm.Free;
    CfgForm := nil;
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FAIContentBuffer := TStringList.Create;
  FIsReceivingAI := False;
  FCurrentAIViewer := nil;
  FMessageCount := 0;
  FGeminiAPI := nil;
  md := TMarkdownProcessor.createDialect(mdCommonMark);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FGeminiAPI.Free;
  FAIContentBuffer.Free;
  md.free;
  // FMessageContainer 会自动释放其子控件
end;

procedure TMainForm.HtmlViewer1KeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  CurrentViewer:  THtmlViewer;
begin
  if (Sender is THtmlViewer) then
    begin
      // 2. 检查是否按下了 Ctrl + C
      if (Key = Ord('C')) and (ssCtrl in Shift) then
      begin
        // 3. 安全转换类型
        CurrentViewer := THtmlViewer(Sender);
        CurrentViewer.CopyToClipboard;

        Key := 0; // 消耗事件，防止向上传递
      end;
    end;
end;

procedure TMainForm.NewConversationClick(Sender: TObject);
var
  i: Integer;
begin
  // 清空所有聊天记录（删除 FMessageContainer 中的所有子控件）
  for i := FMessageContainer.ControlCount - 1 downto 0 do
  begin
    FMessageContainer.Controls[i].Free;
  end;

  // Free 掉 FGeminiAPI
  if Assigned(FGeminiAPI) then
  begin
    FGeminiAPI.Free;
    FGeminiAPI := nil;
  end;

  // 重置相关状态
  FCurrentAIViewer := nil;
  FAIContentBuffer.Clear;
  FIsReceivingAI := False;
  FMessageCount := 0;
end;
end.

