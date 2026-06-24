unit Unit3;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpclient, fpjson, jsonparser;

type

  { TGeminiSSEThread }

  TGeminiSSEThread = class;

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
  CandidatesArray: TJSONArray;
  CandidateObj: TJSONObject;
  ContentObj: TJSONObject;
  PartsArray: TJSONArray;
  PartObj: TJSONObject;
  I, J: Integer;
  Text: string;
  Done: Boolean;
begin
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
          if JSONObj.Find('candidates') is TJSONArray then
          begin
            CandidatesArray := JSONObj.Arrays['candidates'];
            for I := 0 to CandidatesArray.Count - 1 do
            begin
              CandidateObj := CandidatesArray.Objects[I];
              if CandidateObj.Find('content') is TJSONObject then
              begin
                ContentObj := CandidateObj.Objects['content'];
                if ContentObj.Find('parts') is TJSONArray then
                begin
                  PartsArray := ContentObj.Arrays['parts'];
                  for J := 0 to PartsArray.Count - 1 do
                  begin
                    PartObj := PartsArray.Objects[J];
                    if PartObj.Find('text') <> nil then
                      Text := Text + PartObj.Get('text', '');
                  end;
                end;
              end;
              if CandidateObj.Find('finishReason') <> nil then
                Done := True;
            end;
          end;
          if Text <> '' then
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
  ContentObj: TJSONObject;
  PartsArray: TJSONArray;
  PartObj: TJSONObject;
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
      ContentObj := TJSONObject.Create;
      PartsArray := TJSONArray.Create;
      PartObj := TJSONObject.Create;
      PartObj.Add('text', FPrompt);
      PartsArray.Add(PartObj);
      ContentObj.Add('role', 'user');
      ContentObj.Add('parts', PartsArray);
      RequestBody.Add('contents', TJSONArray.Create([ContentObj]));
      RequestJSON := RequestBody.AsJSON;
    finally
      RequestBody.Free;
    end;

    FullURL := FURL;
    if Pos('?key=', FullURL) = 0 then
      FullURL := FullURL + '?key=' + FToken;
    if Pos('alt=sse', FullURL) = 0 then
    begin
      if Pos('?', FullURL) > 0 then
        FullURL := FullURL + '&alt=sse'
      else
        FullURL := FullURL + '?alt=sse';
    end;

    HttpClient.RequestHeaders.Clear;
    HttpClient.RequestHeaders.Add('Content-Type: application/json');
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
var a: Boolean;
begin
  a := Assigned(FThread);
  //a := FThread <> nil;
  Result := a;
end;

end.
