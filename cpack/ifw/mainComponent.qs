/* Main Application Installer Script */

function Component()
{
}

Component.prototype.createOperations = function()
{
	// Call default implementation
	component.createOperations();
	
	// Create a shortcuts on the StartMenu and the Desktop
	if (systemInfo.kernelType === "winnt")
	{
		component.addOperation("CreateShortcut", "@TargetDir@/bin/@ProductName@.exe", "@StartMenuDir@/@ProductName@ @ProductVersion@.lnk");
		component.addOperation("CreateShortcut", "@TargetDir@/bin/@ProductName@.exe", "@DesktopDir@/@ProductName@.lnk");
		component.addOperation("CreateShortcut", "@TargetDir@/maintenancetool.exe", "@StartMenuDir@/Uninstall @ProductName@.lnk");
	}
}
