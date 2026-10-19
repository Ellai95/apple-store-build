"""One_iBot certificate bridge, based on publicly observed oneAPi response fields.
No UDID registration, purchase, Telegram messaging, or IPA publication is performed.
"""
import argparse
import base64
import binascii
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request

from service import https, validate_credential_bytes

REFERENCE_COMMIT = '9efc56ab64dbb9eabc3c031188df4a593ec5b027'
MAX_RESPONSE = 2 * 1024 * 1024


class ProviderError(ValueError):
    pass


def check_udid(udid):
    if not isinstance(udid, str) or not re.fullmatch(r'[A-Za-z0-9-]{1,80}', udid):
        raise ProviderError('Invalid device identifier')


def certificate_payload(response, udid, password_override=None):
    """Validate provider material using the same P12/profile checks as manual enrollment."""
    check_udid(udid)
    rows = response if isinstance(response, list) else [response]
    if not rows or not all(isinstance(row, dict) for row in rows):
        raise ProviderError('Unexpected provider certificate response')
    matches = [row for row in rows if row.get('udid') == udid]
    if len(matches) != 1:
        raise ProviderError('Expected exactly one certificate for the requested device')
    row = matches[0]
    if row.get('revoked') or row.get('enabled') is False or str(row.get('status', '')).lower() in ('revoked', 'disabled', 'expired'):
        raise ProviderError('Provider reports an inactive certificate')
    fields = []
    for name in ('p12', 'mobileprovision'):
        value = row.get(name)
        if not isinstance(value, str) or not value.strip() or value.strip().lower() == 'null':
            raise ProviderError('Certificate not ready: P12 and mobileprovision are both required')
        if len(value) > MAX_RESPONSE:
            raise ProviderError('Certificate package too large')
        try:
            fields.append(base64.b64decode(''.join(value.split()), validate=True))
        except (ValueError, binascii.Error):
            raise ProviderError('Invalid base64 certificate data') from None
    password = password_override if password_override is not None else row.get('p12_password')
    if not isinstance(password, str):
        raise ProviderError('P12 password missing; supply an explicit local password file')
    # Expiry comes from actual certificate/profile bytes, never a marketing plan label.
    try:
        return validate_credential_bytes(fields[0], fields[1], password, udid)
    except Exception:
        raise ProviderError('Certificate validation failed: check password, device, matching pair and expiry') from None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ProviderError('Provider redirect refused; confirm the API origin before retrying')


def fetch_certificate(udid, api_key, origin='https://api.bot1.org'):
    check_udid(udid)
    origin = https(origin).rstrip('/')
    parsed = urllib.parse.urlsplit(origin)
    if parsed.path or parsed.query:
        raise ProviderError('Use the provider root HTTPS origin')
    if not isinstance(api_key, str) or not api_key.strip() or '\n' in api_key or '\r' in api_key:
        raise ProviderError('Set ONE_IBOT_API_KEY locally')
    request = urllib.request.Request(origin + '/certificate?' + urllib.parse.urlencode({'udid': udid}),
                                     headers={'Authorization': api_key, 'Accept': 'application/json'})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
            if response.status != 200:
                raise ProviderError('Provider returned an unexpected response status')
            raw = response.read(MAX_RESPONSE + 1)
        if len(raw) > MAX_RESPONSE:
            raise ProviderError('Provider response too large')
        return json.loads(raw)
    except ProviderError:
        raise
    except urllib.error.HTTPError as error:
        raise ProviderError(f'Provider HTTP {error.code}; credentials and response body were not logged') from None
    except Exception:
        raise ProviderError('Cannot read provider certificate response; no credentials logged') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--udid', required=True)
    parser.add_argument('--origin', default='https://api.bot1.org')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error('Choose a new private output file')
    try:
        result = fetch_certificate(args.udid, os.environ.get('ONE_IBOT_API_KEY'), args.origin)
        # Preserve provider response for local provision-one; never print its contents.
        args.out.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        descriptor = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w', encoding='utf-8') as out:
            json.dump(result, out)
        print('Private provider response saved locally. Validate with provision-one before activation.')
    except (ProviderError, OSError, ValueError):
        parser.exit(1, 'Provider import stopped. Check local API access, response format and output path.\n')


if __name__ == '__main__':
    main()
