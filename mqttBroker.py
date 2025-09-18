import asyncio
from hbmqtt.broker import Broker

async def main():
    config = {
        'listeners': {
            'default': {
                'type': 'tcp',
                'bind': '127.0.0.1:1883'
            }
        },
        'timeout-disconnect-delay': 2,
        'auth': {
            'allow-anonymous': True,
        }
    }
    broker = Broker(config)
    await broker.start()
    print("MQTT Broker started on 127.0.0.1:1883")
    # Keep running
    try:
        await asyncio.Future()  # Run forever
    except KeyboardInterrupt:
        await broker.shutdown()
        print("Broker stopped")

if __name__ == "__main__":
    asyncio.run(main())