## Install

dist folder > mzp > and drag it into a 3ds Max viewport.


```powershell
git clone https://github.com/JuanMaldini/3d-max-scatter.git
cd 3d-max-scatter
powershell -ExecutionPolicy Bypass -File build\dev_link.ps1
```

By default this links into **every** 3ds Max profile it finds on the machine.
Pass `-MaxVersion 2027` (or `-MaxVersion 2024,2027`) to narrow it, or `-Remove`
to uninstall.

## Usage

MaxScatter is a scene object: create it from **Create > Helpers > MaxScatter**
(or the toolbar button, **Customize UI > Toolbars**, category MaxScatter), then
edit it in the **Modify panel** like any native object. Parameters persist in
the .max file.
