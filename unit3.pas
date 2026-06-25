unit Unit3;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpclient, fpjson, jsonparser, opensslsockets, LazLogger;

type

  { TGeminiSSEThread }
  TOnSSEStartEvent = procedure(Sender: TObject) of object;
  TOnSSEDataEvent = procedure(Sender: TObject; const AText: string; IsDone: Boolean) of object;
  TOnSSEErrorEvent = procedure(Sender: TObject; const AError: string) of object;

  TGeminiSSEThread = class(TThread)
  private
    FURL: string;
    FToken: string;
    FPrompt: string;
    FBuffer: string;
    FOnStart: TOnSSEStartEvent;
    FOnData: TOnSSEDataEvent;
    FOnError: TOnSSEErrorEvent;
    AErrorMsg: string;
    procedure DoStart;
    procedure DoData(const AText: string; IsDone: Boolean);
    procedure DoError;
    procedure ProcessSSELine(const ALine: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const AURL, AToken, APrompt: string);
    property OnStart: TOnSSEStartEvent read FOnStart write FOnStart;
    property OnData: TOnSSEDataEvent read FOnData write FOnData;
    property OnError: TOnSSEErrorEvent read FOnError write FOnError;
  end;

  { TGeminiAPI }

  TGeminiAPI = class
  private
    FURL: string;
    FToken: string;
    FThread: TGeminiSSEThread;
    FOnStart: TOnSSEStartEvent;
    FOnData: TOnSSEDataEvent;
    FOnError: TOnSSEErrorEvent;
    procedure OnThreadTerminated(Sender: TObject);
  public
    constructor Create(const AURL, AToken: string);
    destructor Destroy; override;
    procedure SendPrompt(const APrompt: string);
    function IsBusy: Boolean;
    property OnStart: TOnSSEStartEvent read FOnStart write FOnStart;
    property OnData: TOnSSEDataEvent read FOnData write FOnData;
    property OnError: TOnSSEErrorEvent read FOnError write FOnError;
  end;

implementation

{ TGeminiSSEThread }

constructor TGeminiSSEThread.Create(const AURL, AToken, APrompt: string);
begin
  inherited Create(True);
  FURL := AURL;
  FToken := AToken;
  FPrompt := APrompt;
  FreeOnTerminate := True;
end;

procedure TGeminiSSEThread.DoStart;
begin
  if Assigned(FOnStart) then
    FOnStart(Self);
end;

procedure TGeminiSSEThread.DoData(const AText: string; IsDone: Boolean);
begin
  if Assigned(FOnData) then
    FOnData(Self, AText, IsDone);
end;

procedure TGeminiSSEThread.DoError;
begin
  if Assigned(FOnError) then
    FOnError(Self, AErrorMsg);
end;

procedure TGeminiSSEThread.ProcessSSELine(const ALine: string);
var
  JSONData: TJSONData;
  JSONObj: TJSONObject;
  EventType: string;
  DeltaObj: TJSONObject;
  Text: string;
  Done: Boolean;
begin
  DebugLn('line: ' + ALine);
  if Trim(ALine) = '' then Exit;
  if Copy(ALine, 1, 6) = 'data: ' then
  begin
    FBuffer := FBuffer + Copy(ALine, 7);
  end
  else
  begin
    FBuffer := FBuffer + ALine;
  end;

  try
    if Trim(FBuffer) = '[DONE]' then
    begin
      DoData('', True);
      FBuffer := '';
      Exit;
    end;

    try
      JSONData := GetJSON(FBuffer);
      try
        Done := False;
        Text := '';
        if JSONData is TJSONObject then
        begin
          JSONObj := TJSONObject(JSONData);
          EventType := JSONObj.Get('event_type', '');

          if EventType = 'step.delta' then
          begin
            if JSONObj.Find('delta') is TJSONObject then
            begin
              DeltaObj := TJSONObject(JSONObj.Find('delta'));
              if DeltaObj.Get('type', '') = 'text' then
              begin
                Text := DeltaObj.Get('text', '');
              end;
            end;
          end
          else if EventType = 'interaction.completed' then
          begin
            Done := True;
          end;

          if (Text <> '') or Done then // Only call DoData if there's text or if it's done
            DoData(Text, Done);
        end;
      finally
        JSONData.Free;
      end;
    except
      on E: Exception do
      begin
      end;
    end;
  finally
    FBuffer := '';
  end;
end;

procedure TGeminiSSEThread.Execute;
var
  HttpClient: TFPHTTPClient;
  RequestBody: TJSONObject;
  RequestJSON: string;
  FullURL: string;
  ResponseStream: TMemoryStream;
  Buffer: array[0..4095] of Byte;
  BytesRead: Integer;
  LineBuffer: string;
  I: Integer;
  Ch: Char;
begin
  HttpClient := TFPHTTPClient.Create(nil);
  ResponseStream := TMemoryStream.Create;
  try
    RequestBody := TJSONObject.Create;
    try
      RequestBody.Add('model', 'gemini-3.5-flash');
      RequestBody.Add('input', FPrompt);
      RequestBody.Add('stream', True);
      RequestJSON := RequestBody.AsJSON;
    finally
      RequestBody.Free;
    end;

    FullURL := FURL;

    HttpClient.RequestHeaders.Clear;
    HttpClient.RequestHeaders.Add('Content-Type: application/json');
    HttpClient.RequestHeaders.Add('X-goog-api-key: ' + FToken);
    HttpClient.RequestHeaders.Add('Accept: text/event-stream');

    Synchronize(@DoStart);

    try
      HttpClient.FormPost(FullURL, RequestJSON, ResponseStream);
      ResponseStream.Position := 0;

      LineBuffer := '';
      while ResponseStream.Position < ResponseStream.Size do
      begin
        BytesRead := ResponseStream.Read(Buffer, SizeOf(Buffer));
        for I := 0 to BytesRead - 1 do
        begin
          Ch := Char(Buffer[I]);
          if Ch = #10 then
          begin
            ProcessSSELine(LineBuffer);
            LineBuffer := '';
          end
          else if Ch <> #13 then
            LineBuffer := LineBuffer + Ch;
        end;
      end;
      if LineBuffer <> '' then
        ProcessSSELine(LineBuffer);
    except
      on E: Exception do
      begin
        AErrorMsg := E.Message;
        Synchronize(@DoError);
      end;
    end;
  finally
    ResponseStream.Free;
    HttpClient.Free;
  end;
end;

{ TGeminiAPI }

constructor TGeminiAPI.Create(const AURL, AToken: string);
begin
  inherited Create;
  FURL := AURL;
  FToken := AToken;
  FThread := nil;
end;

destructor TGeminiAPI.Destroy;
begin
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    FThread.WaitFor;
  end;
  inherited Destroy;
end;

procedure TGeminiAPI.OnThreadTerminated(Sender: TObject);
begin
  FThread := nil;
end;

procedure TGeminiAPI.SendPrompt(const APrompt: string);
begin
  if Assigned(FThread) then
    raise Exception.Create('API is busy');

  FThread := TGeminiSSEThread.Create(FURL, FToken, APrompt);
  FThread.OnStart := FOnStart;
  FThread.OnData := FOnData;
  FThread.OnError := FOnError;
  FThread.OnTerminate := @OnThreadTerminated;
  FThread.Start;
end;

function TGeminiAPI.IsBusy: Boolean;
begin
  Result := Assigned(FThread);
end;

end.
