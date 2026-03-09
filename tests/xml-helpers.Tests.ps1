BeforeAll {
    . "$PSScriptRoot\..\lib\syntax-helpers.ps1"
}

Describe 'Format-Xml' {
    It 'indents a minified XML string' {
        $xml = '<root><child attr="value">text</child></root>'
        $result = Format-Xml -Xml $xml

        $result | Should -Match 'child'
        $result | Should -Match 'root'
        # Should contain indentation (newlines)
        $result | Should -Match "`r`n"
    }

    It 'returns null/empty for null input' {
        $result = Format-Xml -Xml $null
        $result | Should -BeNullOrEmpty
    }

    It 'returns whitespace for whitespace input' {
        $result = Format-Xml -Xml '   '
        $result | Should -Be '   '
    }

    It 'preserves XML content after formatting' {
        $xml = '<NaaccrData><Patient><Item naaccrId="nameLast">Smith</Item></Patient></NaaccrData>'
        $result = Format-Xml -Xml $xml

        $result | Should -Match 'Smith'
        $result | Should -Match 'nameLast'
        $result | Should -Match 'NaaccrData'
    }

    It 'handles XML with namespace' {
        $xml = '<NaaccrData xmlns="http://naaccr.org/naaccrxml"><Patient><Item naaccrId="nameLast">Doe</Item></Patient></NaaccrData>'
        $result = Format-Xml -Xml $xml

        $result | Should -Match 'Doe'
        $result | Should -Match 'naaccr.org'
    }

    It 'handles XML with declaration' {
        $xml = '<?xml version="1.0" encoding="UTF-8"?><root><child/></root>'
        $result = Format-Xml -Xml $xml

        $result | Should -Match 'xml version'
        $result | Should -Match 'root'
    }
}

Describe 'Script-level constants' {
    It 'defines BoldIds array' {
        $script:BoldIds | Should -Not -BeNullOrEmpty
        $script:BoldIds | Should -Contain 'nameFirst'
        $script:BoldIds | Should -Contain 'nameLast'
        $script:BoldIds | Should -Contain 'dateOfBirth'
        $script:BoldIds | Should -Contain 'primarySite'
    }

    It 'defines TextFieldIds array' {
        $script:TextFieldIds | Should -Not -BeNullOrEmpty
        $script:TextFieldIds | Should -Contain 'textDxProcPath'
        $script:TextFieldIds | Should -Contain 'textRemarks'
        $script:TextFieldIds | Should -Contain 'ehrReporting'
    }
}
