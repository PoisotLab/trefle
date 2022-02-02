clover_df = "virionette.csv" |> CSV.File |> DataFrame
hosts = sort(unique(clover_df.host_species))
viruses = sort(unique(clover_df.virus_genus))
A = zeros(Bool, (length(viruses), length(hosts)))
clover = BipartiteNetwork(A, viruses, hosts)
for clover_row in eachrow(clover_df)
    clover[clover_row.virus_genus, clover_row.host_species] = true
end