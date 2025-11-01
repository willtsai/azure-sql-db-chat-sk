if not exists(select * from sys.symmetric_keys where [name] = '##MS_DatabaseMasterKey##')
begin
    create master key encryption by password = N'V3RYStr0NGP@ssw0rd!';
end
go

if exists(select * from sys.[database_scoped_credentials] where name = '$CONNECTION_AIEMBEDDING_ENDPOINT$')
begin
	drop database scoped credential [$CONNECTION_AIEMBEDDING_ENDPOINT$];
end
go

create database scoped credential [$CONNECTION_AIEMBEDDING_ENDPOINT$]
with identity = 'HTTPEndpointHeaders', secret = '{"api-key":"$CONNECTION_AIEMBEDDING_APIKEY$"}';
go
