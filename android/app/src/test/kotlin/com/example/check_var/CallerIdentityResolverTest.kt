package com.example.check_var

import com.example.check_var.CallerIdentityResolver.CallerType
import org.junit.Assert.assertEquals
import org.junit.Test

class CallerIdentityResolverTest {

    // ── Null / blank → UNDETERMINED ──────────────────────────────
    @Test fun `null input returns UNDETERMINED`() {
        assertEquals(CallerType.UNDETERMINED, CallerIdentityResolver.resolve(null))
    }

    @Test fun `empty string returns UNDETERMINED`() {
        assertEquals(CallerType.UNDETERMINED, CallerIdentityResolver.resolve(""))
    }

    @Test fun `whitespace-only returns UNDETERMINED`() {
        assertEquals(CallerType.UNDETERMINED, CallerIdentityResolver.resolve("   "))
    }

    // ── Private caller patterns → UNKNOWN ────────────────────────
    @Test fun `english Private returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Private"))
    }

    @Test fun `english Unknown returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Unknown"))
    }

    @Test fun `english No Caller ID returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("No Caller ID"))
    }

    @Test fun `english Blocked returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Blocked"))
    }

    @Test fun `english Restricted returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Restricted"))
    }

    @Test fun `english Unavailable returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Unavailable"))
    }

    @Test fun `vietnamese Khong xac dinh returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Không xác định"))
    }

    @Test fun `vietnamese Rieng tu returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Riêng tư"))
    }

    @Test fun `case insensitive matching`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("PRIVATE"))
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("unknown"))
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("không xác định"))
    }

    @Test fun `substring matching catches OEM variants`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Người gọi không xác định"))
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("Số riêng tư"))
    }

    // ── Phone number patterns → UNKNOWN ──────────────────────────
    @Test fun `international number returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("+62 812 345 6789"))
    }

    @Test fun `local number with dashes returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("0812-345-6789"))
    }

    @Test fun `number with parens returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("(021) 345-6789"))
    }

    @Test fun `short emergency number returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("113"))
    }

    @Test fun `digits only returns UNKNOWN`() {
        assertEquals(CallerType.UNKNOWN, CallerIdentityResolver.resolve("08123456789"))
    }

    // ── Contact names → KNOWN_CONTACT ────────────────────────────
    @Test fun `english name returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("Mom"))
    }

    @Test fun `full name returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("John Smith"))
    }

    @Test fun `vietnamese name returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("Nguyễn Văn A"))
    }

    @Test fun `name with emoji returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("Mom ❤️"))
    }

    @Test fun `business name returns KNOWN_CONTACT`() {
        assertEquals(CallerType.KNOWN_CONTACT, CallerIdentityResolver.resolve("Pizza Hut Delivery"))
    }
}
