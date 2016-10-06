defmodule NebulaMetadata.State do

  defstruct host: "127.0.0.1",
            port: 8087,
            bucket_type: <<"cdmi">>,
            bucket_name: <<"cdmi">>,
            bucket: nil,
            cdmi_index: <<"cdmi_idx">>

end
