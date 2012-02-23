﻿namespace RemObjects.Builder.API;

interface
uses
  RemObjects.Builder, RemObjects.Script.EcmaScript, System.Collections.Generic, System.Linq;

type
  JVariables = public class(EcmaScriptObject)
  private
    fOwner: Engine;
  public
    property Owner: Engine read fOwner;
    constructor(aOwner: Engine);
    method DefineOwnProperty(aName: String; aValue: PropertyValue; aThrow: Boolean): Boolean; override;
    method GetOwnProperty(aName: String): PropertyValue; override;
  end;
  Environment = public class(Dictionary<string, Object>)
  private
    fPrevious : RemObjects.Builder.API.Environment; readonly;
    method get_Item(s : String): Object;
    method set_Item(s : String; value: Object);
  public
    constructor; empty;
    method &Add(key: String; value: Object); reintroduce;
    method Clear; reintroduce;
    constructor(aEnv: Environment);
    property Previous: Environment read fPrevious;
    property Item[s: string]: Object read get_Item write set_Item; reintroduce;
    method SetGlobal(aName: string; aValue: Object);
    method LoadIni(aPath: String);
    method LoadSystem;
  end;

  [PluginRegistration]
  EnvironmentRegistration = public class(IPluginRegistration)
  private
  public
    method &Register(aServices: IApiRegistrationServices);
  end;

implementation

method EnvironmentRegistration.&Register(aServices: IApiRegistrationServices);
begin
  var lEnv := new RemObjects.Builder.API.JVariables(aServices.Engine);
  aServices.RegisterValue('env', lEnv);
  aServices.RegisterProperty('wd', -> aServices.Engine.WorkDir, a-> begin aServices.Engine.WorkDir := Utilities.GetObjAsString(a, aServices.Globals.ExecutionContext) end);
  aServices.RegisterValue('export', RemObjects.Builder.Utilities.SimpleFunction(aServices.Engine, a-> begin
    var lValue := a.Skip(1):FirstOrDefault();
    if lValue is EcmaScriptObject then 
    lValue := Utilities.GetObjectAsPrimitive(aSErvices.Globals.ExecutionContext, EcmaScriptObject(lValue), PrimitiveType.None);
    lEnv.Owner.Environment.SetGlobal(a:FirstOrDefault():ToString, lValue);
    exit Undefined.Instance;
  end));
  aServices.RegisterValue('ignoreErrors', RemObjects.Builder.Utilities.SimpleFunction(aServices.Engine, (a, b, c) -> 
    begin 
      try
        result := (c.FirstOrDefault as EcmaScriptObject):Call(a, c.Skip(1):ToArray);
      except
        on e: Exception do begin
          aServices.Engine.Logger.LogError('Ignoring error: '+e);
          result := Undefined.Instance; 
        end;
      end;

    end));
  aServices.RegisterValue('retry', RemObjects.Builder.Utilities.SimpleFunction(aServices.Engine, (a, b, c) -> 
    begin
      var lCount := Utilities.GetArgAsInteger(c, 0, a, false);
      loop begin
        try
          dec(lCount);
          result := (c.Skip(1).FirstOrDefault as EcmaScriptObject):Call(a, c.Skip(2):ToArray);
          break;
        except
          on e: Exception where lCount > 0 do begin
            aServices.Engine.Logger.LogError('Ignoring error: '+e);
            continue;
          end;
        end;
      end;

    end));

 end;

method JVariables.DefineOwnProperty(aName: String; aValue: PropertyValue; aThrow: Boolean): Boolean;
begin
  fOwner.Environment[aName] := aValue:Value;
end;

method JVariables.GetOwnProperty(aName: String): PropertyValue;
begin
  var lValue := fOwner.Environment[aName];
  if lValue = nil then exit nil;
  exit new PropertyValue(PropertyAttributes.Configurable or PropertyAttributes.Enumerable, lValue);
end;

constructor JVariables(aOwner: Engine);
begin
  inherited constructor(aOwner.Engine.GlobalObject);
  fOwner := aOwner;
end;



method Environment.get_Item(s: String): Object;
begin
  var lSelf := self;
  while assigned(lSelf) do begin
    locking lSelf do begin
      if TryGetValue(s, out result) then exit;
    end;
    lSelf := lSelf.Previous;
  end;
end;

method Environment.set_Item(s: String; value: Object);
begin
  locking self do 
    inherited Item[s] := value;
end;

constructor Environment(aEnv: Environment);
begin
  fPrevious := aEnv;
end;

method Environment.LoadIni(aPath: String);
begin
  locking self do begin
    var lIni := new IniFile();
    lIni.LoadFromFile(aPath);
    for each el in lIni.Sections.SelectMany(a->a.Item2, (a,b) -> new Tuple<string, string>(if string.IsNullOrEmpty(a.Item1) then b.Key else a.Item1+'.'+b.Key, b.Value)) do 
      Add(el.Item1, el.Item2);
  end;
end;

method Environment.LoadSystem;
begin
  locking self do begin
    for each el: System.Collections.DictionaryEntry in System.Environment.GetEnvironmentVariables() do begin
      inherited Item[el.Key:ToString] := el.Value:ToString;
    end;
  end;
end;

method Environment.SetGlobal(aName: string; aValue: Object);
begin
var lSelf := self;
  while assigned(lSelf) do begin
    if lSelf.Previous = nil then 
      lSelf[aName] := aValue 
    else
      lSelf.Remove(aName);
    lSelf := lSelf.Previous;
  end;
end;

method Environment.&Add(key: String; value: Object);
begin
  locking self do begin
    inherited Add(key, value);
  end;
end;

method Environment.Clear;
begin
  locking self do inherited Clear;
end;



end.