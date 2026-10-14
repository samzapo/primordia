// Run with: node tests/test_websocket_address.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const client = fs.readFileSync(path.join(__dirname, '../scripts/network/network_client.gd'), 'utf8');
const source = client.split('const BROWSER_SOCKET_ADDRESS := """')[1].split('"""')[0];
const calls = [];
class BrowserSocket {
    static OPEN = 1;
    constructor(address, protocols) {
        const parsed = new URL(address);
        assert(['ws:', 'wss:'].includes(parsed.protocol));
        this.url = address;
        this.protocols = protocols;
        this.binaryType = 'blob';
        calls.push({ address, protocols });
    }
    send(payload) { this.sent = payload; }
}
const window = { WebSocket: BrowserSocket };
const context = vm.createContext({ window, URL, Map, Proxy, Reflect });
const register = address => vm.runInContext(source.replace('%s', JSON.stringify(address)), context);
assert.throws(() => new BrowserSocket('wss://::1:8766/ws'), TypeError);
register('wss://[::1]:8766/ws');
const protocols = ['primordia'];
const socket = new window.WebSocket('wss://::1:8766/ws', protocols);
assert.equal(socket.url, 'wss://[::1]:8766/ws');
assert.equal(socket.protocols, protocols);
assert(socket instanceof BrowserSocket);
assert.equal(window.WebSocket.OPEN, BrowserSocket.OPEN);
socket.binaryType = 'arraybuffer';
const payload = new Uint8Array([1, 2, 3]);
socket.send(payload);
assert.equal(socket.sent, payload);
assert.equal(socket.binaryType, 'arraybuffer');
const adapter = window.WebSocket;
register('wss://[::1]:8766/ws');
assert.equal(window.WebSocket, adapter);
for (const [valid, broken, expected] of [
    ['wss://[2601:19B:401::ABCD]:8766/ws', 'wss://2601:19B:401::ABCD:8766/ws', 'wss://[2601:19B:401::ABCD]:8766/ws'],
    ['wss://[::1]:443/ws?camera=1', 'wss://::1/ws?camera=1', 'wss://[::1]/ws?camera=1'],
    ['ws://[::1]:80/ws', 'ws://::1/ws', 'ws://[::1]/ws'],
    ['wss://[::ffff:192.0.2.1]:8766/ws', 'wss://::ffff:192.0.2.1:8766/ws', 'wss://[::ffff:192.0.2.1]:8766/ws'],
]) {
    register(valid);
    assert.equal(new window.WebSocket(broken).url, expected);
}
// Already valid URLs pass through unchanged, including when a future engine restores brackets.
for (const address of ['wss://[::1]:8766/ws', 'wss://[::1]:443/ws', 'wss://127.0.0.1:8766/ws', 'wss://pond.example:8766/ws']) {
    register(address);
    assert.equal(new window.WebSocket(address).url, address);
}
// Other malformed addresses remain rejected; registration never relaxes URL or TLS validation.
assert.throws(() => new window.WebSocket('wss://2001:db8::1:8766/ws'), TypeError);
const bare = { WebSocket: BrowserSocket };
const plain = vm.createContext({ window: bare, URL, Map, Proxy, Reflect });
vm.runInContext(source.replace('%s', JSON.stringify('wss://pond.example/ws')), plain);
assert.equal(bare.WebSocket, BrowserSocket);
vm.runInContext(source.replace('%s', JSON.stringify('bad address')), plain);
assert.equal(bare.WebSocket, BrowserSocket);
assert.equal(window.primordiaSocketAddress.rewrites, 5);
console.log('WebSocket address checks passed: IPv6, default ports, valid URLs, protocol/binary preservation, idempotence and unregistered rejection.');
