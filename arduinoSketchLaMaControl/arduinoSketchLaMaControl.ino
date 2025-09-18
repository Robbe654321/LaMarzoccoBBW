// UNO R4 WiFi — LM paddle controller via HTTP (INPUT_PULLUP, gesture flush, extra filtering)

#include <WiFiS3.h>

const char* WIFI_SSID = "Willemsens-WiFi";
const char* WIFI_PASS = "1eve111a";

// Pinnen (zoals jij gebruikt)
const int PIN_RL_MAIN   = 4;  // Relay #1
const int PIN_RL_BYPASS = 7;  // Relay #2  (Relay #3 volgt HW)
const int PIN_PADDLE_IN = 3;  // Paddle naar GND, interne PULLUP naar 5V

enum Mode { MODE_AUTO, MODE_MANUAL };
Mode mode = MODE_MANUAL;
bool overrideActive = false;
int  overrideValue  = 0;

// ===== Noise-hardening =====
unsigned long DEBOUNCE_MS = 80;     // was 50 → nu 80ms
unsigned long STABLE_REQ_MS = 40;   // extra low-pass: min 40ms stabiel
unsigned long IGNORE_AFTER_BOOT_MS = 200;

int lastRaw = 0;
int stableState = 0;                 // 0=open, 1=gesloten
int lastStable = 0;
unsigned long lastEdgeCandidateTs = 0;
unsigned long bootMs = 0;

// Auto-flush
bool flushActive = false;
unsigned long flushUntil = 0;

// Gesture-based flush (short paddle tap)
bool gestureFlushEnabled = true;      // kan via /config uitgezet worden
unsigned long GESTURE_FLUSH_MS   = 2000; // duur van flush in ms
unsigned long GESTURE_PULSE_MIN_MS = 60; // minimaal (boven debounce) om tap te tellen
unsigned long GESTURE_PULSE_MAX_MS = 350; // maximaal om als "kort" te gelden
unsigned long lastCloseTs = 0;          // tijdstempel van laatste 0->1 (paddle dicht)

WiFiServer server(80);

inline void setRelayMain(bool on){ digitalWrite(PIN_RL_MAIN,   on ? HIGH : LOW); }
inline void setRelayBypass(bool on){ digitalWrite(PIN_RL_BYPASS, on ? HIGH : LOW); }
inline bool getRelayMain(){ return digitalRead(PIN_RL_MAIN)==HIGH; }

void applyBypass(){
  if (mode == MODE_MANUAL){
    setRelayBypass(false);
    setRelayMain(false);
    flushActive = false;
  } else {
    setRelayBypass(true);
  }
}

void cancelOverrideAndFlush(){
  if (overrideActive) overrideActive = false;
  if (flushActive)    flushActive    = false;
}

void handleLogic(){
  unsigned long now = millis();

  // --- Power-on ignore window ---
  if (now - bootMs < IGNORE_AFTER_BOOT_MS) {
    // houd uitgang fail-safe; lees wel alvast raw zodat we na 200ms schoon starten
    // Lees geïnverteerd: INPUT_PULLUP => open=HIGH(0), dicht=LOW(1)
    lastRaw = (digitalRead(PIN_PADDLE_IN) == LOW ? 1 : 0);
    return;
  }

  // --- Strong filtering: debounce + min stable window ---
  // INPUT_PULLUP: open=HIGH, dicht=LOW ⇒ invert naar open=0, dicht=1
  int raw = (digitalRead(PIN_PADDLE_IN) == LOW ? 1 : 0);  // 0=open, 1=gesloten
  if (raw != lastRaw) {
    lastRaw = raw;
    lastEdgeCandidateTs = now;           // start “kandidaat” overgang
  } else {
    // raw gelijk gebleven; check of lang genoeg stabiel om te accepteren
    if ((now - lastEdgeCandidateTs) >= max(DEBOUNCE_MS, STABLE_REQ_MS)) {
      if (stableState != raw) {
        // Definitieve overgang
        int prev = stableState;
        stableState = raw;

        // Rising edge 0->1: paddle dicht — noteer start voor mogelijke korte tap
        if (prev == 0 && stableState == 1) {
          cancelOverrideAndFlush();
          lastCloseTs = now;
        }
        // Falling edge 1->0: paddle open — detecteer korte tap en start flush
        if (prev == 1 && stableState == 0) {
          if (lastCloseTs > 0) {
            unsigned long pulseMs = now - lastCloseTs;
            if (gestureFlushEnabled && !overrideActive && mode == MODE_AUTO &&
                pulseMs >= GESTURE_PULSE_MIN_MS && pulseMs <= GESTURE_PULSE_MAX_MS) {
              flushActive = true;
              flushUntil = now + GESTURE_FLUSH_MS;
            }
          }
        }

        lastStable = prev;
      }
    }
  }

  // --- Uitgang ---
  if (mode == MODE_AUTO){
    setRelayBypass(true);
    bool mainCmd = false;

    // Override krijgt prioriteit
    if (overrideActive) {
      mainCmd = (overrideValue != 0);
    } else if (flushActive) {
      if (now >= flushUntil) flushActive = false; else mainCmd = true;
    }
    if (!overrideActive && !flushActive) {
      mainCmd = (stableState != 0);
    }

    setRelayMain(mainCmd);
  } else {
    setRelayBypass(false);
    setRelayMain(false);
  }
}

// ===== HTTP utils (ongewijzigd behalve status velden) =====
void sendHttpHeader(WiFiClient &client, const char* contentType="application/json", int code=200, bool cors=true){
  client.print("HTTP/1.1 "); client.print(code); client.println(code==200?" OK":"");
  client.print("Content-Type: "); client.println(contentType);
  client.println("Connection: close");
  if (cors){ client.println("Access-Control-Allow-Origin: *"); client.println("Access-Control-Allow-Methods: GET, OPTIONS"); }
  client.println();
}

void sendJsonStatus(WiFiClient &client){
  char ipbuf[32];
  IPAddress ip = WiFi.localIP();
  snprintf(ipbuf, sizeof(ipbuf), "%u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);

  sendHttpHeader(client, "application/json");
  client.print("{\"mode\":\""); client.print(mode==MODE_AUTO?"AUTO":"MANUAL");
  client.print("\",\"paddle\":"); client.print(stableState);
  client.print(",\"relay_main\":"); client.print((int)getRelayMain());
  client.print(",\"override\":\""); client.print(overrideActive ? (overrideValue? "1":"0") : "off");
  client.print("\",\"flush_active\":"); client.print(flushActive ? "true":"false");
  client.print(",\"gesture_enabled\":"); client.print(gestureFlushEnabled ? "true":"false");
  client.print(",\"gesture_flush_ms\":"); client.print(GESTURE_FLUSH_MS);
  client.print(",\"gesture_pulse_min_ms\":"); client.print(GESTURE_PULSE_MIN_MS);
  client.print(",\"gesture_pulse_max_ms\":"); client.print(GESTURE_PULSE_MAX_MS);
  client.print(",\"debounce_ms\":"); client.print(DEBOUNCE_MS);
  client.print(",\"stable_req_ms\":"); client.print(STABLE_REQ_MS);
  client.print(",\"boot_ignore_ms\":"); client.print(IGNORE_AFTER_BOOT_MS);
  client.print(",\"ip\":\""); client.print(ipbuf);
  client.print("\",\"uptime_ms\":"); client.print(millis() - bootMs);
  client.println("}");
}

String getQueryValue(const String& query, const String& key){
  String k = key + "=";
  int i = query.indexOf(k); if (i<0) return "";
  int j = query.indexOf('&', i); if (j<0) j = query.length();
  return query.substring(i + k.length(), j);
}
String urlDecode(const String &s){
  String out; out.reserve(s.length());
  for (size_t i=0;i<s.length();++i){
    char c=s[i];
    if (c=='+' ){ out+=' '; }
    else if (c=='%' && i+2<s.length()){
      auto hexv=[&](char h)->int{ if('0'<=h&&h<='9')return h-'0'; if('a'<=h&&h<='f')return h-'a'+10; if('A'<=h&&h<='F')return h-'A'+10; return 0; };
      out += char((hexv(s[i+1])<<4)|hexv(s[i+2])); i+=2;
    } else out+=c;
  }
  return out;
}

void sendHome(WiFiClient &client){
  sendHttpHeader(client, "text/html");
  client.println(F(
    "<!doctype html><html><head><meta name=viewport content='width=device-width,initial-scale=1'>"
    "<style>body{font-family:system-ui;margin:16px}button{padding:12px 16px;margin:6px;font-size:16px}"
    "input{padding:8px;margin:6px;width:100px}</style></head><body>"
    "<h2>LM Paddle Controller</h2><pre id='s'></pre>"
    "<p><button onclick=\"go('/mode?set=AUTO')\">AUTO</button>"
    "<button onclick=\"go('/mode?set=MANUAL')\">MANUAL</button></p>"
    "<p><button onclick=\"go('/override?set=1')\">override:1</button>"
    "<button onclick=\"go('/override?set=0')\">override:0</button>"
    "<button onclick=\"go('/override?set=off')\">override:off</button></p>"
    "<p>Flush: <input id='ms' type='number' value='2000'> ms <button onclick=\"flushMs()\">Start flush</button></p>"
    "<p>Debounce: <input id='db' type='number' value='80'> ms, Stable: <input id='st' type='number' value='40'> ms "
    "<button onclick=\"setFilt()\">Set filters</button></p>"
    "<script>"
    "async function refresh(){const r=await fetch('/status'); const j=await r.json();"
    "document.getElementById('s').innerText=JSON.stringify(j,null,2);} "
    "async function go(u){await fetch(u); setTimeout(refresh,150);} "
    "async function flushMs(){const v=document.getElementById('ms').value||'2000'; await fetch('/flush?ms='+v); setTimeout(refresh,150);} "
    "async function setFilt(){const d=document.getElementById('db').value||'80'; const s=document.getElementById('st').value||'40'; "
    "await fetch('/config?debounce_ms='+d+'&stable_ms='+s); setTimeout(refresh,150);} "
    "setInterval(refresh,1000); refresh();"
    "</script></body></html>"
  ));
}

void handleHttp(){
  WiFiClient client = server.available();
  if (!client) return;

  String reqLine = client.readStringUntil('\n'); reqLine.trim();
  while (client.connected()){ String h = client.readStringUntil('\n'); if (h=="\r" || h.length()==1) break; }

  String method, path; int sp1 = reqLine.indexOf(' '), sp2 = reqLine.indexOf(' ', sp1+1);
  if (sp1<=0 || sp2<=sp1){ sendHttpHeader(client,"text/plain",400); client.println("Bad Request"); client.stop(); return; }
  method = reqLine.substring(0, sp1);
  path   = reqLine.substring(sp1+1, sp2);

  String route = path, query=""; int qpos = path.indexOf('?');
  if (qpos>=0){ route = path.substring(0,qpos); query = path.substring(qpos+1); }
  route = urlDecode(route); query = urlDecode(query);

  if (route=="/"){ sendHome(client); }
  else if (route=="/status"){ sendJsonStatus(client); }
  else if (route=="/mode"){
    String setVal = getQueryValue(query, "set"); setVal.toUpperCase();
    if (setVal=="AUTO")   mode = MODE_AUTO;
    if (setVal=="MANUAL") mode = MODE_MANUAL;
    applyBypass(); sendJsonStatus(client);
  }
  else if (route=="/override"){
    String setVal = getQueryValue(query, "set"); setVal.toLowerCase();
    if (setVal=="off"){ overrideActive=false; }
    else if (setVal=="1"){ overrideActive=true; overrideValue=1; }
    else if (setVal=="0"){ overrideActive=true; overrideValue=0; }
    sendJsonStatus(client);
  }
  else if (route=="/flush"){
    unsigned long dur = 2000;
    String ms = getQueryValue(query,"ms"); String sc = getQueryValue(query,"sec");
    if (ms.length()) dur = (unsigned long) ms.toInt();
    else if (sc.length()) dur = (unsigned long) (sc.toInt()*1000UL);
    if (mode == MODE_AUTO && dur>0){ flushActive = true; flushUntil = millis() + dur; }
    sendJsonStatus(client);
  }
  else if (route=="/config"){
    String db = getQueryValue(query,"debounce_ms");
    String st = getQueryValue(query,"stable_ms");
    String gf = getQueryValue(query,"gesture"); // on/off/1/0
    String fm = getQueryValue(query,"flush_ms");
    String gmin = getQueryValue(query,"pulse_min_ms");
    String gmax = getQueryValue(query,"pulse_max_ms");
    if (db.length()){ unsigned long v = (unsigned long) db.toInt(); if (v>=5 && v<=500) DEBOUNCE_MS = v; }
    if (st.length()){ unsigned long v = (unsigned long) st.toInt(); if (v>=0 && v<=500) STABLE_REQ_MS = v; }
    if (gf.length()){
      String v = gf; v.toLowerCase();
      gestureFlushEnabled = (v=="1" || v=="on" || v=="true");
    }
    if (fm.length()){ unsigned long v = (unsigned long) fm.toInt(); if (v>=200 && v<=10000) GESTURE_FLUSH_MS = v; }
    if (gmin.length()){ unsigned long v = (unsigned long) gmin.toInt(); if (v>=0 && v<=1000) GESTURE_PULSE_MIN_MS = v; }
    if (gmax.length()){ unsigned long v = (unsigned long) gmax.toInt(); if (v>=0 && v<=2000) GESTURE_PULSE_MAX_MS = v; }
    sendJsonStatus(client);
  }
  else { sendHttpHeader(client,"text/plain",404); client.println("Not found"); }

  client.stop();
}

void setup(){
  Serial.begin(115200);
  pinMode(PIN_RL_MAIN,   OUTPUT);
  pinMode(PIN_RL_BYPASS, OUTPUT);
  pinMode(PIN_PADDLE_IN, INPUT_PULLUP);  // interne pull-up, open=HIGH

  mode = MODE_MANUAL;
  setRelayMain(false);
  setRelayBypass(false);

  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("WiFi verbinden");
  for (int i=0;i<60 && WiFi.status()!=WL_CONNECTED;i++){ delay(200); Serial.print("."); }
  Serial.println();
  if (WiFi.status()==WL_CONNECTED){ Serial.print("IP: "); Serial.println(WiFi.localIP()); }
  else { Serial.println("WiFi failed."); }

  server.begin();
  bootMs = millis();
}

void loop(){
  handleLogic();
  handleHttp();
  delay(2);
}
