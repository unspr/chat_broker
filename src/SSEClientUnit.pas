unit SSEClientUnit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, httpsend, ssl_openssl3;

type

  TSSEEvent = record
    EventType: string;
    Data: string;
  end;

  TOnSSEEvent = procedure(Sender: TObject; const AEvent: TSSEEvent) of object;
  TOnSSEOpen = procedure(Sender: TObject) of object;
  TOnSSEClose = procedure(Sender: TObject) of object;
  TOnSSEError = procedure(Sender: TObject; const AError: string) of object;

  TSSEClientThread = class(TThread)
  private
    FURL: string;
    FHeaders: TStringList;
    FRequestBody: string;
    FProxyHost: string;
    FProxyPort: Word;
    FOnEvent: TOnSSEEvent;
    FOnOpen: TOnSSEOpen;
    FOnClose: TOnSSEClose;
    FOnError: TOnSSEError;
    FCurrentEvent: TSSEEvent; // Moved from local to field
    AErrorMsg: string;
    procedure DoOpen;
    procedure DoClose;
    procedure DoEvent; // No parameters
    procedure DoError;
    procedure ProcessSSELine(const ALine: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const AURL: string; AHeaders: TStringList; const ARequestBody: string; const AProxyHost: string; const AProxyPort: Word);
    destructor Destroy; override;
    property OnEvent: TOnSSEEvent read FOnEvent write FOnEvent;
    property OnOpen: TOnSSEOpen read FOnOpen write FOnOpen;
    property OnClose: TOnSSEClose read FOnClose write FOnClose;
    property OnError: TOnSSEError read FOnError write FOnError;
  end;

  TSSEClient = class
  private
    FThread: TSSEClientThread;
    FURL: string;
    FHeaders: TStringList;
    FRequestBody: string;
    FOnEvent: TOnSSEEvent;
    FOnOpen: TOnSSEOpen;
    FOnClose: TOnSSEClose;
    FOnError: TOnSSEError;
    procedure OnThreadTerminated(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const AURL: string; AHeaders: TStringList; const ARequestBody: string; const AProxyHost: string; const AProxyPort: Word);
    procedure Disconnect;
    function IsActive: Boolean;
    property OnEvent: TOnSSEEvent read FOnEvent write FOnEvent;
    property OnOpen: TOnSSEOpen read FOnOpen write FOnOpen;
    property OnClose: TOnSSEClose read FOnClose write FOnClose;
    property OnError: TOnSSEError read FOnError write FOnError;
  end;

implementation

{ TSSEClientThread }

constructor TSSEClientThread.Create(const AURL: string; AHeaders: TStringList; const ARequestBody: string; const AProxyHost: string; const AProxyPort: Word);
begin
  inherited Create(True);
  FURL := AURL;
  FRequestBody := ARequestBody;
  FHeaders := TStringList.Create;
  if Assigned(AHeaders) then
    FHeaders.Assign(AHeaders);
  FProxyHost := AProxyHost;
  FProxyPort := AProxyPort;
  FreeOnTerminate := True;
  FillChar(FCurrentEvent, SizeOf(FCurrentEvent), 0);
end;

destructor TSSEClientThread.Destroy;
begin
  FHeaders.Free;
  inherited Destroy;
end;

procedure TSSEClientThread.DoOpen;
begin
  if Assigned(FOnOpen) then
    FOnOpen(Self);
end;

procedure TSSEClientThread.DoClose;
begin
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

procedure TSSEClientThread.DoEvent;
begin
  if Assigned(FOnEvent) then
    FOnEvent(Self, FCurrentEvent);
end;

procedure TSSEClientThread.DoError;
begin
  if Assigned(FOnError) then
    FOnError(Self, AErrorMsg);
end;

procedure TSSEClientThread.ProcessSSELine(const ALine: string);
var
  ColonPos: Integer;
  Field: string;
  Value: string;
  // CurrentEvent: TSSEEvent;  // Removed local variable
begin
  if Trim(ALine) = '' then // End of an event
  begin
    if (FCurrentEvent.Data <> '') or (FCurrentEvent.EventType <> '') then
      Synchronize(@DoEvent); // Fixed Synchronize call
    FillChar(FCurrentEvent, SizeOf(FCurrentEvent), 0); // Clear FCurrentEvent
    Exit;
  end;

  ColonPos := Pos(':', ALine);
  if ColonPos > 0 then
  begin
    Field := Trim(Copy(ALine, 1, ColonPos - 1));
    Value := Trim(Copy(ALine, ColonPos + 1, Length(ALine) - ColonPos));

    if Field = 'event' then
      FCurrentEvent.EventType := Value
    else if Field = 'data' then
    begin
      if FCurrentEvent.Data <> '' then
        FCurrentEvent.Data := FCurrentEvent.Data + #10 + Value
      else
        FCurrentEvent.Data := Value;
    end;
    // TODO: Handle 'id' and 'retry' fields if needed
  end;
end;

procedure TSSEClientThread.Execute;
var
  HttpClient: THTTPSend;
  ResponseStream: TMemoryStream;
  Buffer: array[0..4095] of Byte;
  BytesRead: Integer;
  LineBuffer: string;
  I: Integer;
  Ch: Char;
begin
  HttpClient := THTTPSend.Create;
  HttpClient.ProxyHost := FProxyHost;
  HttpClient.ProxyPort := IntToStr(FProxyPort);
  HttpClient.Timeout := 10000;
  HttpClient.KeepAlive := True;
  ResponseStream := TMemoryStream.Create;
  try
    HttpClient.Headers.Add('Accept: text/event-stream');
    if Assigned(FHeaders) then
    begin
      for I := 0 to FHeaders.Count - 1 do
        HttpClient.Headers.Add(FHeaders[I]);
    end;

    Synchronize(@DoOpen);

    try
      if FRequestBody = '' then
        HttpClient.HTTPMethod('GET', FURL)
      else
      begin
        HttpClient.Document.Clear;
        HttpClient.Document.Write(PByte(FRequestBody)^, Length(FRequestBody));
        HttpClient.MimeType := 'application/json';
        HttpClient.HTTPMethod('POST', FURL);
      end;

      ResponseStream.CopyFrom(HttpClient.Document, 0);
      ResponseStream.Position := 0;

      LineBuffer := '';
      while not Terminated and (ResponseStream.Position < ResponseStream.Size) do
      begin
        BytesRead := ResponseStream.Read(Buffer, SizeOf(Buffer));
        for I := 0 to BytesRead - 1 do
        begin
          Ch := Char(Buffer[I]);
          if Ch = #10 then // LF
          begin
            ProcessSSELine(LineBuffer);
            LineBuffer := '';
          end
          else if Ch <> #13 then // CR
            LineBuffer := LineBuffer + Ch;
        end;
      end;
      // Process any remaining data after the loop (if no trailing LF)
      if (LineBuffer <> '') and not Terminated then
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
    Synchronize(@DoClose);
  end;
end;

{ TSSEClient }

constructor TSSEClient.Create;
begin
  inherited Create;
  FThread := nil;
  FHeaders := TStringList.Create;
end;

destructor TSSEClient.Destroy;
begin
  Disconnect;
  FHeaders.Free;
  inherited Destroy;
end;

procedure TSSEClient.OnThreadTerminated(Sender: TObject);
begin
  FThread.Free;
  FThread := nil;
end;

procedure TSSEClient.Connect(const AURL: string; AHeaders: TStringList; const ARequestBody: string; const AProxyHost: string; const AProxyPort: Word);
begin
  if IsActive then
    Exit;

  FURL := AURL;
  FRequestBody := ARequestBody;
  FHeaders.Assign(AHeaders);

  FThread := TSSEClientThread.Create(FURL, FHeaders, FRequestBody, AProxyHost, AProxyPort);
  FThread.OnOpen := FOnOpen;
  FThread.OnClose := FOnClose;
  FThread.OnEvent := FOnEvent;
  FThread.OnError := FOnError;
  FThread.OnTerminate := @OnThreadTerminated;
  FThread.Start;
end;

procedure TSSEClient.Disconnect;
begin
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    FThread.WaitFor;
  end;
end;

function TSSEClient.IsActive: Boolean;
begin
  Result := Assigned(FThread) and not FThread.Terminated; // Fixed: Changed from FThread.Running
end;

end.
