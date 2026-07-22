unit gemini;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, LazLogger, SSEClientUnit;

type
  TOnSSEStartEvent = procedure(Sender: TObject) of object;
  TOnSSEDataEvent = procedure(Sender: TObject; const AText: string; IsDone: Boolean) of object;
  TOnSSEErrorEvent = procedure(Sender: TObject; const AError: string) of object;
  TOnInteractionIdReceived = procedure(Sender: TObject; const AInteractionId: string) of object;

  { TGeminiAPI }

  TGeminiAPI = class
  private
    FSSEClient: TSSEClient;
    FURL: string;
    FToken: string;
    FModel: string;
    FProxyHost: string;
    FProxyPort: Word;
    FPreviousInteractionId: string; // Stores the interaction ID for conversation continuation
    FOnStart: TOnSSEStartEvent;
    FOnData: TOnSSEDataEvent;
    FOnError: TOnSSEErrorEvent;
    procedure OnInteractionIdReceived(Sender: TObject; const AInteractionId: string);
    procedure SSEClientEvent(Sender: TObject; const AEvent: TSSEEvent);
  public
    constructor Create(const AURL, AToken, AModel: string; const AProxyHost: string; const AProxyPort: Word);
    destructor Destroy; override;
    procedure SendPrompt(const APrompt: string);
    function IsBusy: Boolean;
    property OnStart: TOnSSEStartEvent read FOnStart write FOnStart;
    property OnData: TOnSSEDataEvent read FOnData write FOnData;
    property OnError: TOnSSEErrorEvent read FOnError write FOnError;
  end;

implementation

{ TGeminiAPI }

procedure TGeminiAPI.SSEClientEvent(Sender: TObject; const AEvent: TSSEEvent);
var
  JSONData: TJSONData;
  JSONObj: TJSONObject;
  EventType: string;
  DeltaObj: TJSONObject;
  Text: string;
  InteractionIdObj: TJSONObject;
  InteractionId: string;
begin
  DebugLn('SSEClientEvent - Type: ' + AEvent.EventType + ', Data: ' + AEvent.Data);
  if AEvent.Data = '' then Exit;

  try
    if Trim(AEvent.Data) = '[DONE]' then
    begin
      Exit;
    end;

    try
      JSONData := GetJSON(AEvent.Data);
      try
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
                if (Text <> '') then
                begin
                  FOnData(self, Text, False);
                end;
              end;
            end;
          end
          else if EventType = 'interaction.completed' then
          begin
            FOnData(self, '', True);
            // Extract and save interaction ID for next request
            InteractionIdObj := nil;
            if JSONObj.Find('interaction') is TJSONObject then
            begin
              InteractionIdObj := TJSONObject(JSONObj.Find('interaction'));
              try
                InteractionId := InteractionIdObj.Get('id', '');
                if InteractionId <> '' then
                begin
                  DebugLn('Extracted interaction ID: ' + InteractionId);
                  FPreviousInteractionId := InteractionId;
                end;
              except
                on E: Exception do
                  DebugLn('Error extracting interaction ID: ' + E.Message);
              end;
            end;
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

procedure TGeminiAPI.SendPrompt(const APrompt: string);
var
  RequestBody: TJSONObject;
  RequestJSON: string;
  Headers: TStringList;
begin
  FSSEClient.OnOpen := FOnStart;
  FSSEClient.OnEvent := @SSEClientEvent;
  FSSEClient.OnError := FOnError;
  
  Headers := TStringList.Create;
  try
    RequestBody := TJSONObject.Create;
    try
      RequestBody.Add('model', FModel);
      RequestBody.Add('system_instruction', 'Please answer me using mdCommonMark');
      RequestBody.Add('input', APrompt);
      RequestBody.Add('stream', True);

      // Add previous_interaction_id if available
      if FPreviousInteractionId <> '' then
        RequestBody.Add('previous_interaction_id', FPreviousInteractionId);

      RequestJSON := RequestBody.AsJSON;
    finally
      RequestBody.Free;
    end;

    Headers.Add('Content-Type: application/json');
    Headers.Add('X-goog-api-key: ' + FToken);

    FSSEClient.Connect(FURL, Headers, RequestJSON, FProxyHost, FProxyPort);
  finally
    Headers.Free;
  end;
end;

constructor TGeminiAPI.Create(const AURL, AToken, AModel: string; const AProxyHost: string; const AProxyPort: Word);
begin
  inherited Create;
  FURL := AURL;
  FToken := AToken;
  FModel := AModel;
  FProxyHost := AProxyHost;
  FProxyPort := AProxyPort;
  FSSEClient := TSSEClient.Create;
end;

destructor TGeminiAPI.Destroy;
begin
  FSSEClient.Free;
  inherited Destroy;
end;

procedure TGeminiAPI.OnInteractionIdReceived(Sender: TObject; const AInteractionId: string);
begin
  FPreviousInteractionId := AInteractionId;
  DebugLn('Stored interaction ID for next request: ' + FPreviousInteractionId);
end;

function TGeminiAPI.IsBusy: Boolean;
begin
  Result := FSSEClient.isActive;
end;

end.
