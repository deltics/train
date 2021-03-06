﻿namespace RemObjects.Train.API;

interface
uses RemObjects.Train,
  System.Collections.Generic, System.Diagnostics, RemObjects.Script.EcmaScript;
type
  [PluginRegistration]
  ShellRegistration = public class(IPluginRegistration)
  private
  public
    method &Register(aServices: IApiRegistrationServices);
  end;

  MyProcess = public class(Process)
  private
  public
    property Killed: Boolean;
  end;


  Shell = public class
  private
    fEngine: IApiRegistrationServices;

  public
    class method ExecuteProcess(aCommand, aArgs, AWD: String; aComSpec: Boolean; 
      aTargetError: Action<String>; aTargetOutput: Action<String>; 
      environment: array of KeyValuePair<String, String>; 
      aTimeout: nullable TimeSpan;
      aUseProcess: Process := nil): Integer;
    constructor(aItem: IApiRegistrationServices);
    method Exec(ec: RemObjects.Script.EcmaScript.ExecutionContext; aSelf: Object; args: array of Object): Object;
    method ExecAsync(ec: RemObjects.Script.EcmaScript.ExecutionContext; aSelf: Object; args: array of Object): Object;
    method INTSystem(ec: RemObjects.Script.EcmaScript.ExecutionContext; aSelf: Object; args: array of Object): Object;
    method Kill(ec: RemObjects.Script.EcmaScript.ExecutionContext; aSelf: Object; args: array of Object): Object;
  end;

implementation

method Shell.Exec(ec: RemObjects.Script.EcmaScript.ExecutionContext; aSelf: Object; args: array of Object): Object;
begin
  var lCMD := fEngine.ResolveWithBase(ec, Utilities.GetArgAsString(args, 0, ec), true);
  var lFail := true;
  var lArg := fEngine.Expand(ec, Utilities.GetArgAsString(args, 1, ec));
  var lOpt := Utilities.GetArgAsEcmaScriptObject(args, 2, ec);
  var lEnv := new List<KeyValuePair<String, String>>;
  var lTimeout: nullable TimeSpan := nil;
  var lCaptureMode: Boolean := false;
  var lCaptureFunc: EcmaScriptBaseFunctionObject := nil;
  var LWD: String := nil;
  if lOpt <> nil then begin
    var lVal := lOpt.Get('capture');
    if (lVal <> nil) and (lVal <> Undefined.Instance) then begin
      lCaptureFunc := EcmaScriptBaseFunctionObject(lVal);
      if (lCaptureFunc = nil) and (Utilities.GetObjAsBoolean(lVal, ec)) then begin
        lCaptureMode := true;
      end;
    end;
    lVal := lOpt.Get('workdir');
    if lVal is String then
      LWD := fEngine.ResolveWithBase(ec,String (lVal), true);

    lVal := lOpt.Get('timeout');
    if (lVal <> nil) and (lVal <> Undefined.Instance) then 
      lTimeout := TimeSpan.FromSeconds(Utilities.GetObjAsInteger(lVal, ec));
    lVal := lOpt.Get('environment');
    var lObj := EcmaScriptObject(lVal);
    if lObj  <> nil then begin
      for each el in lObj.Values do begin
        lEnv.Add(new KeyValuePair<String,String>(el.Key, Utilities.GetObjAsString(el.Value.Value, ec)));
      end;
    end;
  end;

  fEngine.Engine.Logger.Enter(true,'shell.exec', lCMD+if not String.IsNullOrEmpty(lArg) then ' '+ lArg else '');
  try
    if fEngine.Engine.DryRun then begin
      fEngine.Engine.Logger.LogMessage('Dry run.');
      exit '';
    end;
    var sb := new System.Text.StringBuilder;
    var lExit := ExecuteProcess(lCMD, lArg, coalesce(LWD, fEngine.Engine.WorkDir),false , a-> begin
      locking(sb) do begin
        sb.AppendLine(a);
      end;
      if assigned(lCaptureFunc) then begin
        try
          lCaptureFunc.Call(ec, a);
        except
        end;
      end;
    end, a-> begin
      locking(sb) do sb.AppendLine(a);
      if assigned(lCaptureFunc) then begin
        try
          lCaptureFunc.Call(ec, a);
        except
        end;
      end;
    end, lEnv.ToArray, lTimeout);
    if 0 <> lExit then begin
      var lErr := 'Failed with error code: '+lExit;
      fEngine.Engine.Logger.LogError(lErr);
      fEngine.Engine.Logger.LogMessage('Output: '#13#10+sb.ToString);
      raise new Exception(lErr);
    end;
    fEngine.Engine.Logger.LogInfo('Output: '#13#10+sb.ToString);
    lFail := false;
    if lCaptureMode then 
      exit sb.ToString()
    else
      exit Undefined.Instance;
  except
    on e: Exception do begin
      fEngine.Engine.Logger.LogError('Error when calling Process.Execute: '+e.Message);
      raise new AbortException;
    end;
  finally
    fEngine.Engine.Logger.Exit(true,String.Format('shell.exec({0})', lCMD), if lFail then RemObjects.Train.FailMode.Yes else RemObjects.Train.FailMode.No);
  end;
end;

method Shell.ExecAsync(ec: RemObjects.Script.EcmaScript.ExecutionContext; aSelf: Object; args: array of Object): Object;
begin
  var lCMD := fEngine.ResolveWithBase(ec, Utilities.GetArgAsString(args, 0, ec), true);
  var lArg := fEngine.Expand(ec, Utilities.GetArgAsString(args, 1, ec));
  var lFail := true;
  var lOpt := Utilities.GetArgAsEcmaScriptObject(args, 2, ec);
  var lEnv := new List<KeyValuePair<String, String>>;
  var lTimeout: nullable TimeSpan := nil;
  var lWD: String;
  if lOpt <> nil then begin
    var lVal := lOpt.Get('timeout');
    if (lVal <> nil) and (lVal <> Undefined.Instance) then 
      lTimeout := TimeSpan.FromSeconds(Utilities.GetObjAsInteger(lVal, ec));
    lVal := lOpt.Get('workdir');
    if lVal is String then
      lWD := fEngine.ResolveWithBase(ec,String (lVal), true);
    lVal := lOpt.Get('environment');
    var lObj := EcmaScriptObject(lVal);
    if lObj  <> nil then begin
      for each el in lObj.Values do begin
        lEnv.Add(new KeyValuePair<String,String>(el.Key, Utilities.GetObjAsString(el.Value.Value, ec)));
      end;
    end;
  end;
  var lLogger := new RemObjects.Train.DelayedLogger;
  var lProc := new MyProcess;
  var lTask := new System.Threading.Tasks.Task(method begin
    lLogger.Enter(true,String.Format('shell.execAsync({0})', lCMD), lArg);
    try
      if fEngine.Engine.DryRun then begin
        lLogger.LogMessage('Dry run.');
        exit '';
      end;
      var sb := new System.Text.StringBuilder;
      var lExit := ExecuteProcess(lCMD, lArg, coalesce(lWD, fEngine.Engine.WorkDir), false, a-> begin
        locking(sb) do begin
          sb.AppendLine(a);
        end;
      end, a-> begin
        locking(sb) do sb.AppendLine(a);
      end, lEnv.ToArray, lTimeout, lProc);
      lLogger.LogInfo('Output: '#13#10+sb.ToString);
      if lProc.Killed then exit;
      if 0 <> lExit then begin
        var lErr := 'Failed with error code: '+lExit;
        lLogger.LogError(lErr);
        raise new AbortException();
      end;
      lFail := false;
    finally
      lLogger.Exit(true,String.Format('shell.execAsync({0})', lCMD), if lFail then RemObjects.Train.FailMode.Yes else RemObjects.Train.FailMode.No, nil);
    end;
  end);
  fEngine.RegisterTask(lTask, String.Format('[{0}] {1} {2}', lTask.Id, lCMD, lArg), lLogger);
  lTask.Start();
  exit new TaskWrapper(fEngine.Engine.Engine.GlobalObject, fEngine.AsyncWorker.TaskProto, Task := lTask, Process := lProc);
end;

method Shell.Kill(ec: RemObjects.Script.EcmaScript.ExecutionContext; aSelf: Object; args: array of Object): Object;
begin
  var lArg := TaskWrapper(Utilities.GetArg(args, 0));
  if (lArg = nil) or (lArg.Process = nil) then raise new Exception('No async process passed!');

  try
    MyProcess(lArg.Process).Killed := true;
    lArg.Process.Kill;
  except
  end;
  lArg.Process := nil;
  try
    lArg.Task.Wait();
  except
  end;
  fEngine.UnregisterTask(lArg.Task);

  exit Undefined.Instance;
end;


method Shell.INTSystem(ec: RemObjects.Script.EcmaScript.ExecutionContext; aSelf: Object; args: array of Object): Object;
begin
  var lArg := fEngine.Expand(ec, Utilities.GetArgAsString(args, 0, ec));
  var lWD := if length(args) < 2 then nil else fEngine.ResolveWithBase(ec, Utilities.GetArgAsString(args, 1, ec), true);
  var lFail := true;
  fEngine.Engine.Logger.Enter(true,'shell.system()', lArg+' WD: '+lWD);
  try
    if fEngine.Engine.DryRun then begin
      fEngine.Engine.Logger.LogMessage('Dry run.');
      exit '';
    end;
    var sb := new System.Text.StringBuilder;
    var lExit := ExecuteProcess(nil, lArg, coalesce(lWD, fEngine.Engine.WorkDir),true , a-> begin
      locking(sb) do sb.AppendLine(a);
    end, a-> begin
      locking(sb) do sb.AppendLine(a)
    end, nil, nil);
    fEngine.Engine.Logger.LogInfo('Output: '#13#10+sb.ToString);
    if 0 <> lExit then begin
      var lErr := 'Failed with error code: '+lExit;
      fEngine.Engine.Logger.LogError(lErr);
      raise new AbortException;
    end;
    lFail := false;
    exit sb.ToString();
  finally
    fEngine.Engine.Logger.Exit(true,'shell.system()', if lFail then RemObjects.Train.FailMode.Yes else RemObjects.Train.FailMode.No);
  end;
end;

constructor Shell(aItem: IApiRegistrationServices);
begin
  fEngine := aItem;
end;

class method Shell.ExecuteProcess(aCommand: String; aArgs, AWD: String; aComSpec: Boolean; aTargetError: Action<String>; aTargetOutput: Action<String>; environment: array of KeyValuePair<String, String>; aTimeout: nullable TimeSpan; aUseProcess: Process): Integer;
begin
  var lProcess := coalesce(aUseProcess, new Process());
  if lProcess.StartInfo = nil then lProcess.StartInfo := new ProcessStartInfo();
  if aComSpec then begin
    lProcess.StartInfo.FileName := if MUtilities.Windows then coalesce(System.Environment.GetEnvironmentVariable('COMSPEC'), 'CMD.EXE') else coalesce(System.Environment.GetEnvironmentVariable('SHELL'), '/bin/sh');
    if String.IsNullOrEmpty(aCommand) then begin
      lProcess.StartInfo.Arguments := (if not MUtilities.Windows then '-c ' else '/C ')+ aArgs;
    end else begin
      if not aCommand.StartsWith('"') then 
        aCommand := '"'+aCommand.Replace('"', '""')+'"';
      lProcess.StartInfo.Arguments := (if not MUtilities.Windows then '-c ' else '/C ')+ aCommand+' '+aArgs;
    end;
  end else begin
    lProcess.StartInfo.FileName := aCommand;
    lProcess.StartInfo.Arguments := aArgs;
  end;

  if assigned(AWD) then
    lProcess.StartInfo.WorkingDirectory := AWD;
  lProcess.StartInfo.UseShellExecute := false;
  if aTargetError <> nil then begin
    lProcess.StartInfo.RedirectStandardError := true;
    lProcess.ErrorDataReceived += method (o: Object; ar: DataReceivedEventArgs) begin
      aTargetError:Invoke(ar.Data);
    end;
  end;
  if aTargetOutput <> nil then begin
    lProcess.StartInfo.RedirectStandardOutput := true;
    lProcess.OutputDataReceived += method (o: Object; ar: DataReceivedEventArgs) begin
      aTargetOutput:Invoke(ar.Data);
    end;
  end;

  for each el in environment do begin
    lProcess.StartInfo.EnvironmentVariables[el.Key] := el.Value;
  end;

  try 
    if not lProcess.Start then raise new Exception('Could not start process');
    if aTargetOutput <> nil then lProcess.BeginOutputReadLine;
    if aTargetError <> nil then lProcess.BeginErrorReadLine;
    try
      if aTimeout = nil then
        lProcess.WaitForExit()
      else 
        if not lProcess.WaitForExit(Integer(aTimeout.TotalMilliseconds)) then raise new Exception('Timeout!');
      exit lProcess.ExitCode;
    except
      on e: System.ComponentModel.Win32Exception do ;
      on e: SystemException do;
    end;
  finally
    aTargetError := nil;
    aTargetOutput := nil;
    lProcess.Dispose;
  end;
end;

method ShellRegistration.&Register(aServices: IApiRegistrationServices);
begin

  var lInstance := new Shell(aServices);
  aServices.RegisterValue('shell', 
    new RemObjects.Script.EcmaScript.EcmaScriptObject(aServices.Globals)
  .AddValue('cd', RemObjects.Train.MUtilities.SimpleFunction(aServices.Engine, (a, b, c) -> 
    begin
      var lCurrPath := aServices.Engine.WorkDir;
      var lPath := aServices.ResolveWithBase(a, RemObjects.Script.EcmaScript.Utilities.GetArgAsString(c, 0, a), true);
      try
        if System.IO.Path.IsPathRooted(lPath) then 
          aServices.Engine.WorkDir := lPath
        else
          aServices.Engine.WorkDir  := System.IO.Path.Combine(aServices.Engine.WorkDir, lPath);
      except
        on e: Exception do begin
          aServices.Logger.LogError(e);
          raise new AbortException;
        end;
      end;

      var lFunc := RemObjects.Script.EcmaScript.Utilities.GetArgAsEcmaScriptObject(c, 1, a);
      if lFunc <> nil then
      try 
        lFunc.Call(a);
      finally
        aServices.Engine.WorkDir := lCurrPath;
      end;
    end))
  .AddValue('exec', RemObjects.Train.MUtilities.SimpleFunction(aServices.Engine, @lInstance.Exec))
  .AddValue('execAsync', RemObjects.Train.MUtilities.SimpleFunction(aServices.Engine, @lInstance.ExecAsync))
  .AddValue('kill', RemObjects.Train.MUtilities.SimpleFunction(aServices.Engine, @lInstance.Kill))
  .AddValue('system', RemObjects.Train.MUtilities.SimpleFunction(aServices.Engine, @lInstance.INTSystem)));
end;

end.
