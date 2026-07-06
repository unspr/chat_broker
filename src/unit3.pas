unit Unit3;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, LazLogger, SSEClientUnit;

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
    FProxyHost: string;
    FProxyPort: Word;
    FSSEClient: TSSEClient;
    FOnStart: TOnSSEStartEvent;
    FOnData: TOnSSEDataEvent;
    FOnError: TOnSSEErrorEvent;
    AErrorMsg: string;
    FSyncedText: string; // New: for Synchronize parameter passing
    FSyncedDone: Boolean; // New: for Synchronize parameter passing
    procedure DoStart;
    procedure DoData(const AText: string; IsDone: Boolean);
    procedure DoError;
    procedure DoDataSync; // New: Parameterless method for Synchronize
    procedure SSEClientEvent(Sender: TObject; const AEvent: TSSEEvent);
    procedure SSEClientOpen(Sender: TObject);
    procedure SSEClientError(Sender: TObject; const AError: string);
    procedure SSEClientClose(Sender: TObject); // New: Named method for OnClose
  protected
    procedure Execute; override;
  public
    constructor Create(const AURL, AToken, APrompt: string; const AProxyHost: string; const AProxyPort: Word);
    destructor Destroy; override; // Added destructor
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
    FProxyHost: string;
    FProxyPort: Word;
    FOnStart: TOnSSEStartEvent;
    FOnData: TOnSSEDataEvent;
    FOnError: TOnSSEErrorEvent;
    procedure OnThreadTerminated(Sender: TObject);
  public
    constructor Create(const AURL, AToken: string; const AProxyHost: string; const AProxyPort: Word);
    destructor Destroy; override;
    procedure SendPrompt(const APrompt: string);
    function IsBusy: Boolean;
    property OnStart: TOnSSEStartEvent read FOnStart write FOnStart;
    property OnData: TOnSSEDataEvent read FOnData write FOnData;
    property OnError: TOnSSEErrorEvent read FOnError write FOnError;
  end;

implementation

{ TGeminiSSEThread }

constructor TGeminiSSEThread.Create(const AURL, AToken, APrompt: string; const AProxyHost: string; const AProxyPort: Word);
begin
  inherited Create(True);
  FURL := AURL;
  FToken := AToken;
  FPrompt := APrompt;
  FProxyHost := AProxyHost;
  FProxyPort := AProxyPort;
  FreeOnTerminate := True;

  FSSEClient := TSSEClient.Create;
  FSSEClient.OnOpen := @SSEClientOpen;   // Fixed: Added @
  FSSEClient.OnEvent := @SSEClientEvent; // Fixed: Added @
  FSSEClient.OnError := @SSEClientError; // Fixed: Added @
  FSSEClient.OnClose := @SSEClientClose; // Fixed: Assign named method with @
end;

destructor TGeminiSSEThread.Destroy;
begin
  FSSEClient.Free;
  inherited Destroy;
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

procedure TGeminiSSEThread.DoDataSync;
begin
  DoData(FSyncedText, FSyncedDone);
end;

procedure TGeminiSSEThread.SSEClientOpen(Sender: TObject);
begin
  Synchronize(@DoStart);
end;

procedure TGeminiSSEThread.SSEClientError(Sender: TObject; const AError: string);
begin
  AErrorMsg := AError;
  Synchronize(@DoError);
end;

procedure TGeminiSSEThread.SSEClientClose(Sender: TObject); // Implementation for the new named method
begin
  Terminate;
end;

procedure TGeminiSSEThread.SSEClientEvent(Sender: TObject; const AEvent: TSSEEvent);
var
  JSONData: TJSONData;
  JSONObj: TJSONObject;
  EventType: string;
  DeltaObj: TJSONObject;
  Text: string;
  Done: Boolean;
begin
  DebugLn('SSEClientEvent - Type: ' + AEvent.EventType + ', Data: ' + AEvent.Data);
  if AEvent.Data = '' then Exit;

  try
    if Trim(AEvent.Data) = '[DONE]' then
    begin
      DoData('', True);
      Exit;
    end;

    try
      JSONData := GetJSON(AEvent.Data);
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

          if (Text <> '') or Done then
          begin
            FSyncedText := Text;
            FSyncedDone := Done;
            Synchronize(@DoDataSync);
          end;
        end;
      finally
        JSONData.Free;
      end;
    except
      on E: Exception do
      begin
        DebugLn('JSON parsing error in SSEClientEvent: ' + E.Message);
      end;
    end;
  finally
    // FBuffer := ''; // FBuffer is no longer used here
  end;
end;

procedure TGeminiSSEThread.Execute;
var
  RequestBody: TJSONObject;
  RequestJSON: string;
  Headers: TStringList;
begin
  Headers := TStringList.Create;
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

    Headers.Add('Content-Type: application/json');
    Headers.Add('X-goog-api-key: ' + FToken);

    FSSEClient.Connect(FURL, Headers, RequestJSON, FProxyHost, FProxyPort);

    // Wait for the SSEClient to finish or for the thread to be terminated externally
    while not Terminated and FSSEClient.IsActive do
    begin
      Sleep(100);
    end;
    FSSEClient.Disconnect;
  finally
    Headers.Free;
  end;
end;

{ TGeminiAPI }

constructor TGeminiAPI.Create(const AURL, AToken: string; const AProxyHost: string; const AProxyPort: Word);
begin
  inherited Create;
  FURL := AURL;
  FToken := AToken;
  FProxyHost := AProxyHost;
  FProxyPort := AProxyPort;
  FThread := nil;
end;

destructor TGeminiAPI.Destroy;
begin
  if Assigned(FThread) then
    begin
      FThread.Terminate;
      FThread.WaitFor;
      FThread.Free;
      FThread := nil;
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
  begin
    //if FThread.Running then // This will be changed to not FThread.Terminated
    //  Exit; // Still busy with previous request
    FThread.Free; // Free previous thread if not running
    FThread := nil;
  end;
  FThread := TGeminiSSEThread.Create(FURL, FToken, APrompt, FProxyHost, FProxyPort);
  FThread.OnStart := FOnStart;
  FThread.OnData := FOnData;
  FThread.OnError := FOnError;
  FThread.OnTerminate := @OnThreadTerminated;
  FThread.Start;
end;

function TGeminiAPI.IsBusy: Boolean;
begin
  Result := Assigned(FThread) and not FThread.Terminated; // Fixed: Changed from FThread.Running
end;

end.
