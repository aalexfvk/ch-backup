"""
Create zookeeper root node for ClickHouse before start
"""

from kazoo.client import KazooClient
import subprocess

if __name__ == "__main__":
    client = KazooClient('{{conf.zk.uri}}:{{conf.zk.port}}')
    client.start()
    client.ensure_path('/{{instance_name}}')
    client.stop()

    subprocess.Popen(['supervisord', '-c', '/etc/supervisor/supervisord.conf']).wait()
