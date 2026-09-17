<?php
/**
 * Where signed documents live on the server.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

class CMPOD_Storage {

	const FOLDER = 'cindermark-pod';

	/**
	 * Base directory for stored documents.
	 *
	 * Defining CMPOD_STORAGE_DIR in wp-config.php moves everything outside the
	 * web root, which is the only way to be certain the files are not served
	 * directly. Otherwise they sit in uploads behind a deny rule.
	 *
	 * @return string
	 */
	public static function base_dir() {
		if ( defined( 'CMPOD_STORAGE_DIR' ) && CMPOD_STORAGE_DIR ) {
			return rtrim( CMPOD_STORAGE_DIR, '/\\' );
		}
		$uploads = wp_upload_dir();
		return rtrim( $uploads['basedir'], '/\\' ) . '/' . self::FOLDER;
	}

	/**
	 * @return bool
	 */
	public static function is_outside_web_root() {
		return defined( 'CMPOD_STORAGE_DIR' ) && CMPOD_STORAGE_DIR;
	}

	/**
	 * @return string
	 */
	public static function protection_notice() {
		if ( self::is_outside_web_root() ) {
			return __( 'Documents are stored outside the web root and can only be read through the WordPress admin.', 'cindermark-pod' );
		}
		return __( 'Documents are stored in uploads behind a deny rule and are served only through the admin download link. The deny rule is honoured by Apache and LiteSpeed; on nginx, add an equivalent location block or define CMPOD_STORAGE_DIR in wp-config.php to move the folder outside the web root.', 'cindermark-pod' );
	}

	/**
	 * Creates the base directory and drops in the guards.
	 *
	 * @return bool
	 */
	public static function ensure_base_dir() {
		$base = self::base_dir();
		if ( ! wp_mkdir_p( $base ) ) {
			return false;
		}

		$htaccess = $base . '/.htaccess';
		if ( ! file_exists( $htaccess ) ) {
			$rules = "# Signed delivery records. Served only through the WordPress admin.\n"
				. "<IfModule mod_authz_core.c>\n\tRequire all denied\n</IfModule>\n"
				. "<IfModule !mod_authz_core.c>\n\tOrder allow,deny\n\tDeny from all\n</IfModule>\n";
			file_put_contents( $htaccess, $rules );
		}

		$index = $base . '/index.php';
		if ( ! file_exists( $index ) ) {
			file_put_contents( $index, "<?php\n// Silence is golden.\n" );
		}

		return true;
	}

	/**
	 * Year/month subdirectory for a signing timestamp.
	 *
	 * @param int $timestamp Unix time.
	 * @return string|WP_Error Absolute path.
	 */
	public static function month_dir( $timestamp ) {
		if ( ! self::ensure_base_dir() ) {
			return new WP_Error( 'cmpod_storage', __( 'The delivery storage folder could not be created.', 'cindermark-pod' ) );
		}
		$dir = self::base_dir() . '/' . gmdate( 'Y', $timestamp ) . '/' . gmdate( 'm', $timestamp );
		if ( ! wp_mkdir_p( $dir ) ) {
			return new WP_Error( 'cmpod_storage', __( 'The delivery storage folder could not be created.', 'cindermark-pod' ) );
		}
		self::ensure_base_dir();
		return $dir;
	}

	/**
	 * Writes one file.
	 *
	 * The caller supplies a name built from values it has already validated;
	 * this still runs it through sanitize_file_name and refuses anything that
	 * tries to climb out of the directory.
	 *
	 * @param string $dir       Absolute directory.
	 * @param string $filename  Desired file name.
	 * @param string $bytes     File contents.
	 * @return string|WP_Error Absolute path written.
	 */
	public static function write( $dir, $filename, $bytes ) {
		$filename = sanitize_file_name( $filename );
		if ( '' === $filename || false !== strpos( $filename, '..' ) ) {
			return new WP_Error( 'cmpod_storage', __( 'Refused an unsafe file name.', 'cindermark-pod' ) );
		}
		$path = trailingslashit( $dir ) . $filename;
		$written = file_put_contents( $path, $bytes );
		if ( false === $written ) {
			return new WP_Error( 'cmpod_storage', __( 'The delivery document could not be written to disk.', 'cindermark-pod' ) );
		}
		@chmod( $path, 0640 );
		return $path;
	}

	/**
	 * Path relative to the base directory, which is what gets stored in post
	 * meta. Absolute paths break the moment a site is moved or migrated.
	 *
	 * @param string $absolute
	 * @return string
	 */
	public static function relative_path( $absolute ) {
		$base = trailingslashit( self::base_dir() );
		if ( 0 === strpos( $absolute, $base ) ) {
			return substr( $absolute, strlen( $base ) );
		}
		return basename( $absolute );
	}

	/**
	 * @param string $relative
	 * @return string
	 */
	public static function absolute_path( $relative ) {
		return trailingslashit( self::base_dir() ) . ltrim( $relative, '/' );
	}

	/**
	 * Confirms the bytes really are what the app said they were, so a signed
	 * request can never plant an executable file in the uploads folder.
	 *
	 * @param string $bytes
	 * @param string $kind  'pdf' or 'png'.
	 * @return bool
	 */
	public static function looks_like( $bytes, $kind ) {
		return CMPOD_Storage_Sniff::looks_like( $bytes, $kind );
	}
}
