# pip install paho-mqtt
import threading, sys, time
from paho.mqtt import client as mqtt

BROKER = "broker.hivemq.com"   # publieke test broker
PORT   = 1883

TOPIC_MODE_GET   = "lm/paddle/mode"
TOPIC_MODE_SET   = "lm/paddle/mode/set"
TOPIC_STATE      = "lm/paddle/state"
TOPIC_RELAY_MAIN = "lm/paddle/relay_main"
TOPIC_CMD        = "lm/paddle/cmd"

def on_connect(client, userdata, flags, rc, properties=None):
    print(f"[MQTT] connected rc={rc}")
    client.subscribe([(TOPIC_MODE_GET,0),(TOPIC_STATE,0),(TOPIC_RELAY_MAIN,0)])

def on_message(client, userdata, msg):
    print(f"[MQTT] {msg.topic} -> {msg.payload.decode('utf-8', 'ignore')}")

def pub(client, topic, msg):
    client.publish(topic, msg, qos=0, retain=False)
    print(f"[PUB] {topic} = {msg}")

def input_loop(client):
    help_text = (
        "\nControls:\n"
        "  a = AUTO\n"
        "  m = MANUAL\n"
        "  1 = override:1 (force MAIN ON)\n"
        "  0 = override:0 (force MAIN OFF)\n"
        "  o = override:off (disable override)\n"
        "  q = quit\n"
    )
    print(help_text)
    while True:
        ch = sys.stdin.readline().strip().lower()
        if ch == "a":
            pub(client, TOPIC_MODE_SET, "AUTO")
        elif ch == "m":
            pub(client, TOPIC_MODE_SET, "MANUAL")
        elif ch == "1":
            pub(client, TOPIC_CMD, "override:1")
        elif ch == "0":
            pub(client, TOPIC_CMD, "override:0")
        elif ch == "o":
            pub(client, TOPIC_CMD, "override:off")
        elif ch == "q":
            print("Bye")
            client.disconnect()
            break
        else:
            print(help_text)

def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="tester-lm-paddle")
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(BROKER, PORT, keepalive=30)
    t = threading.Thread(target=input_loop, args=(client,), daemon=True)
    t.start()
    try:
        client.loop_forever()
    except KeyboardInterrupt:
        client.disconnect()

if __name__ == "__main__":
    main()
