-- 03_money_grants.test.sql (pgTAP) - STATUS: ditulis, BELUM dijalankan.
begin;
select plan(5);
select is(public.record_money_grant(7530260164,'helper','kasihuang',111,500000,true,null), 'recorded', '1. helper pertama kali: tercatat');
select is(public.record_money_grant(7530260164,'helper','kasihuang',111,100,true,null), 'duplicate', '2. helper ke pemain yang sama lagi: ditolak');
select is(public.record_money_grant(7530260164,'helper','kasihsaldo',111,100,true,null), 'recorded', '3. perintah lain ke pemain yang sama: boleh');
select is(public.record_money_grant(7530260164,'helper','kasihuang',222,100,true,null), 'recorded', '4. pemain lain: boleh');
select is(public.record_money_grant(8841765649,'administrator','kasihuang',111,1000000,false,null), 'recorded', '5. admin tidak dibatasi "sekali"');
select * from finish();
rollback;
