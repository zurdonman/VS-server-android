/**
 * Preload for Node that makes the server-side extension system treat Termux
 * (where process.platform is "android") as a regular Linux environment, so
 * server extensions install instead of being rejected as unsupported.
 *
 * Usage:
 *   NODE_OPTIONS="--require /path/to/android-as-linux.js" code-server
 *
 * (scripts/termux-start.sh does this for you; set CS_ANDROID_AS_LINUX=0 to
 * disable it.) Note Android and Linux are not 100% compatible: extensions with
 * native dependencies or direct OS access may misbehave.
 */
Object.defineProperty(process, 'platform', {
	get() {
		return 'linux';
	},
});
