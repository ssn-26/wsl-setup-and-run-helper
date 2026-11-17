// =============================================================================
// WSL Control Panel - the launcher, "WSL Control Panel.exe".
//
// A small Windows program that runs app\windows\WSL-Control-Panel.ps1 inside
// itself (PowerShell is part of Windows, so nothing is installed). There is
// no console window, and Task Manager and the taskbar show "WSL Control
// Panel" with its own icon instead of "Windows PowerShell".
//
// install.ps1 compiles this file on your PC with the C# compiler that comes
// with Windows (.NET Framework 4), so no ready-made .exe is downloaded.
// "--validate" builds the window without showing it (used by CI).
//
// Keep this file plain ASCII and C# 5 (the compiler that ships with Windows).
// =============================================================================
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("WSL Control Panel")]
[assembly: AssemblyProduct("WSL Control Panel")]
[assembly: AssemblyDescription("A Windows control panel for WSL2")]

static class Launcher
{
    const string Title = "WSL Control Panel";

    [STAThread]
    static int Main(string[] args)
    {
        bool validate = args.Length > 0 && args[0] == "--validate";
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(Path.Combine(Path.Combine(dir, "app"), "windows"), "WSL-Control-Panel.ps1");
        if (!File.Exists(script))
        {
            return Fail(validate, "app\\windows\\WSL-Control-Panel.ps1 was not found next to this program:\n" + dir +
                "\n\nInstall the panel again to repair it.");
        }

        try
        {
            using (Runspace rs = RunspaceFactory.CreateRunspace())
            {
                // The window needs a single-threaded apartment, on this thread.
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    // Only for this process, like "powershell -ExecutionPolicy Bypass".
                    // The last output is the script's exit code.
                    ps.AddScript(
                        "try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch { }\n" +
                        "$global:LASTEXITCODE = 0\n" +
                        "& $args[0] -Validate:$args[1] | Out-String -Stream\n" +
                        "$global:LASTEXITCODE")
                      .AddArgument(script)
                      .AddArgument(validate);
                    var output = ps.Invoke();

                    int code = 0;
                    var text = new StringBuilder();
                    for (int i = 0; i < output.Count; i++)
                    {
                        object o = output[i] == null ? null : output[i].BaseObject;
                        if (i == output.Count - 1 && o is int) { code = (int)o; }
                        else if (o != null) { text.AppendLine(o.ToString()); }
                    }
                    var errors = new StringBuilder();
                    foreach (ErrorRecord e in ps.Streams.Error) { errors.AppendLine(e.ToString()); }

                    if (validate)
                    {
                        Console.Out.Write(text.ToString());
                        Console.Error.Write(errors.ToString());
                        if (errors.Length > 0 && code == 0) { code = 1; }
                    }
                    // Without -Validate the window has already shown its own errors.
                    return code;
                }
            }
        }
        catch (Exception ex)
        {
            return Fail(validate, "The WSL Control Panel could not start:\n\n" + ex.Message);
        }
    }

    static int Fail(bool validate, string message)
    {
        if (validate) { Console.Error.WriteLine(message); }
        else { MessageBox.Show(message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error); }
        return 1;
    }
}
