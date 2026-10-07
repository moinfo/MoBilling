<x-mail::layout :tenantBranding="$tenantBranding ?? null">
    {{-- Header --}}
    <x-slot:header>
        <x-mail::header :url="$tenantBranding['url'] ?? config('app.url')">
            {{ $tenantBranding['name'] ?? config('app.name') }}
        </x-mail::header>
    </x-slot:header>

    {{-- Body --}}
    {{ $slot }}

    {{-- Subcopy --}}
    @isset($subcopy)
        <x-slot:subcopy>
            <x-mail::subcopy>
                {{ $subcopy }}
            </x-mail::subcopy>
        </x-slot:subcopy>
    @endisset

    {{-- Footer --}}
    <x-slot:footer>
        <x-mail::footer>
@if(!empty($tenantBranding['footer_text']))
{{ $tenantBranding['footer_text'] }}
@else
© {{ date('Y') }} {{ $tenantBranding['name'] ?? config('app.name') }}. @lang('All rights reserved.')
@endif
        </x-mail::footer>
    </x-slot:footer>
</x-mail::layout>
