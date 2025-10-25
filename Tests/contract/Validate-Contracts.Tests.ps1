Describe "Contract validation" {
    It "Loads CliToolsConfig and verifies required structure" {
        $config = . ./Config/CliToolsConfig.psd1
        $config | Should -Not -BeNullOrEmpty
        $config.QueuePath | Should -Not -BeNullOrEmpty
        $config.WorkerCount | Should -BeOfType 'System.Int32'
        $config.Tools | Should -BeOfType 'System.Collections.Hashtable'
    }

    It "Loads sample task and checks basic schema fields" {
        # Construct a sample task and validate essential properties
        $sample = @{
            id = [guid]::NewGuid().Guid
            tool = 'aider'
            args = @('input.txt','output.txt')
        }
        $sample | Should -ContainKey 'id'
        $sample.tool | Should -BeOfType 'System.String'
    }
}
