# Driver Essentials

Instalador PowerShell para detectar o PC e buscar drivers essenciais no Windows 10 e Windows 11.

## O que ele faz

- Detecta fabricante, modelo, placa-mae, CPU, GPU e adaptadores de rede.
- Usa a API nativa do Windows Update/Microsoft Update para procurar drivers.
- Baixa e instala drivers classificados como `Driver`.
- Tenta ferramentas oficiais por fabricante quando possivel:
  - Dell Command Update
  - Lenovo System Update
  - HP Support Assistant
  - Intel Driver & Support Assistant
- Cria log e inventario de drivers em `C:\ProgramData\DriverEssentials\DriverUpdate`.
- Mostra dispositivos que ainda ficaram com problema.

## Aviso importante

Nenhum script consegue prometer 100% dos drivers de qualquer PC do mundo. Este projeto busca o maximo seguro por fontes oficiais, sem driver packs de terceiros.

## Comando cola-e-roda

Cole no PowerShell. Ele baixa o script, pede permissao de Administrador pelo UAC e executa:

```powershell
$u='https://raw.githubusercontent.com/SrYakuza6695/Driver-Essentials/main/Driver-Essentials.ps1';$p=Join-Path $env:TEMP 'Driver-Essentials.ps1';Invoke-WebRequest $u -UseBasicParsing -OutFile $p;Start-Process PowerShell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$p`""
```

## Uso local

Abra o PowerShell como Administrador e rode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Driver-Essentials.ps1
```

Somente baixar, sem instalar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Driver-Essentials.ps1 -DownloadOnly
```

Permitir reinicio automatico quando necessario:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Driver-Essentials.ps1 -AutoReboot
```

## Licenca/uso

Perfil do dono: SrYakuza6695.

E proibido vender, revender, empacotar comercialmente ou distribuir este codigo como produto pago sem autorizacao expressa do perfil SrYakuza6695.
