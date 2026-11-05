# Conexión gráfica de ChatGPT

## Uso

En Ajustes → Pulido del texto con ChatGPT, activar el pulido si estaba apagado
no conecta cuentas automáticamente. Pulsar **Conectar ChatGPT** inicia el OAuth
en el navegador mediante el CLI oficial instalado. **Cancelar conexión** detiene
la espera local; no hace logout ni revoca una sesión ya completada. El plazo es
5 minutos. No hace falta abrir Terminal.

Con ruta vacía se conservan las rutas anteriores y se añade
`~/.hermes/node/bin/codex` como **último fallback**, después de nvm y del PATH
resuelto por el shell de login. Una ruta explícita tiene prioridad, incluso si es
inválida: no se sustituye silenciosamente por otro ejecutable. No se modifica el
PATH persistente, el registro de ajustes ni la instalación del CLI.

Si existe una sesión de ChatGPT, Dilo la conserva. Una sesión con API key se
bloquea sin cerrarla ni reemplazarla. Estados desconocidos o errores de
configuración no se interpretan como ausencia de sesión. El estado «listo» solo
acredita credenciales locales reconocidas, no su vigencia o el éxito de pulir un
dictado.

## Decisión y privacidad

[Referencia oficial del CLI](https://developers.openai.com/codex/cli/reference#codex-login):
`codex login` sin opciones abre el navegador para OAuth ChatGPT. Se prefiere este
flujo al protocolo app-server para no recibir ni gestionar URLs/tokens en Dilo.
El login se lanza con `posix_spawn`, sin shell, con stdin/stdout/stderr en `/dev/null`, en el
directorio vacío usado por el pulido. Dilo no registra su salida, no abre Terminal,
no acepta claves ni lee archivos de autenticación. Codex gestiona y guarda la
sesión en el Mac del usuario; su propio almacenamiento/logging no lo controla Dilo.
Se eliminan `OPENAI_API_KEY`, `CODEX_API_KEY` y `CODEX_ACCESS_TOKEN` del entorno
entregado a codex. La comprobación de estado no se presenta en bruto en la UI.

No se inicia OAuth al arrancar ni al comprobar estado. Conexiones simultáneas,
refresco y cambio de ruta desde Ajustes quedan excluidos durante el flujo.
El login nace atómicamente en un grupo POSIX propio. Cancelar/timeout corta ese
grupo con SIGKILL (también el hijo de un wrapper npm que ignore SIGTERM); no hay
escalada diferida que pueda apuntar a un PID reutilizado. Se espera al líder sin
recogerlo (`waitid` + `WNOWAIT`) y se recoge tras cerrar el grupo (`waitpid`). No
se matan otros Codex ni el grupo de Dilo. Un descendiente que se separe deliberadamente
en otra sesión/grupo queda fuera de esta garantía; el wrapper npm normal no lo hace.
Nunca se ejecuta `logout` ni se revocan sesiones ya completadas.

**Concurrencia externa (límite explícito):** la comprobación evita reemplazar una
sesión observada, no constituye una transacción con el almacenamiento de Codex.
Si otra app guarda credenciales después de `login status` y antes/durante `login`,
el CLI puede competir por ellas. Repetir el preflight reduce pero no cierra esa
ventana. No se añade un candado ficticio que las otras apps ignoren, ni se leen,
copian, bloquean o restauran credenciales para intentar resolverla. Ajustes y README
avisan de no iniciar conexiones desde otra app simultáneamente. La prueba de sesión
existente cubre solo la observada en el preflight, no una cuenta externa concurrente.

## Pruebas reproducibles

- `python3 -m unittest discover -s Tests -p 'test_*.py' -v`: recursos, integridad,
  scripts y conservación de fuentes ajenas al delta explícito.
- `./scripts/selftest.sh` en macOS: pruebas Swift originales más el controlador y
  proceso reales usando únicamente un CLI **sintético**, ajustes en suite aislada,
  HOME/CODEX_HOME/TMPDIR temporales y entorno permitido explícito, sin cuentas,
  navegador ni tráfico OAuth. La búsqueda de ejecutable inyecta rutas de sistema
  y resolución de shell sintéticas: nunca consulta instalaciones del runner.
  Se limpian temporales y preferencias antes de `exit`, también con suite roja. Verifica éxito,
  releer después de salida 0, API key/sesión existente/estado desconocido,
  ejecutable ausente, fallo de help, cancelación, doble clic, timeout con SIGTERM
  ignorado, reintento, precedencia nvm/shell/Hermes y conservación íntegra de ajustes.
  Un wrapper con hijo separado que ignora TERM prueba primero persistencia normal;
  cancelar/timeout deben impedir su marcador diferido y dejar ambos PID ausentes,
  conservando un proceso testigo ajeno al grupo.
- El runner exige ausencia del marcador sintético de autorización en stdout y
  stderr; el proceso sintético sí lo emite por ambos canales.
- `scripts/test-codex-login-mutation.py`: elimina la guarda de sesión en una copia,
  compila y exige fallo concreto por reemplazar sesiones ChatGPT/API key. No
  cuenta un fallo de compilación como prueba de la guarda. Otra mutación mata solo
  el padre: la suite debe detectar específicamente la persistencia tardía del hijo.
- CI existente `dilo-macos.yml`: ejecuta estas pruebas en Apple Silicon, compila la
  app completa, firma ad hoc y verifica empaquetado y Core ML.

Pendiente de usuario: apertura real del navegador, consentimiento y callback en
el Mac de Christian, y un dictado con pulido. Ninguna prueba sintética acredita
esos hitos ni la disponibilidad del servicio ChatGPT. La interfaz completa no se
ha validado visualmente en el Mac del usuario.
