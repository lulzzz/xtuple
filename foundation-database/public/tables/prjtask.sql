select xt.add_column('prjtask', 'prjtask_created',      'TIMESTAMP WITH TIME ZONE', NULL, 'public');
select xt.add_column('prjtask', 'prjtask_lastupdated',  'TIMESTAMP WITH TIME ZONE', NULL, 'public');
select xt.add_column('prjtask','prjtask_priority_id', 'integer', 'references incdtpriority (incdtpriority_id)', 'public', 'Project Task Priority');
select xt.add_column('prjtask','prjtask_pct_complete', 'numeric', null, 'public', 'Project Task Percent Complete');

