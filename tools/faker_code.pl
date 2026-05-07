# =============================================================================
# Faker — generates realistic fake data (names, addresses, emails, phone numbers)
# No external API calls — all data is embedded.
# =============================================================================

my $type = $args->{type} // 'user';

# ---------------------------------------------------------------------------
# Embedded data (100+ items each)
# ---------------------------------------------------------------------------
my @first_names = (
    'James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda',
    'David','Elizabeth','William','Barbara','Richard','Susan','Joseph','Jessica',
    'Thomas','Sarah','Christopher','Karen','Charles','Lisa','Daniel','Nancy',
    'Matthew','Betty','Anthony','Margaret','Mark','Sandra','Donald','Ashley',
    'Steven','Dorothy','Paul','Kimberly','Andrew','Emily','Joshua','Donna',
    'Kenneth','Michelle','Kevin','Carol','Brian','Amanda','George','Melissa',
    'Timothy','Deborah','Ronald','Stephanie','Edward','Rebecca','Jason','Sharon',
    'Jeffrey','Laura','Ryan','Cynthia','Jacob','Kathleen','Gary','Amy',
    'Nicholas','Angela','Eric','Shirley','Jonathan','Anna','Stephen','Brenda',
    'Larry','Pamela','Justin','Emma','Scott','Nicole','Brandon','Helen',
    'Benjamin','Samantha','Samuel','Katherine','Frank','Christine','Raymond','Debra',
    'Gregory','Rachel','Alexander','Carolyn','Patrick','Janet','Jack','Catherine',
    'Dennis','Maria','Jerry','Heather','Tyler','Diane','Aaron','Ruth'
);

my @last_names = (
    'Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis',
    'Rodriguez','Martinez','Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas',
    'Taylor','Moore','Jackson','Martin','Lee','Perez','Thompson','White',
    'Harris','Sanchez','Clark','Ramirez','Lewis','Robinson','Walker','Young',
    'Allen','King','Wright','Scott','Torres','Nguyen','Hill','Flores',
    'Green','Adams','Nelson','Baker','Hall','Rivera','Campbell','Mitchell',
    'Carter','Roberts','Gomez','Phillips','Evans','Turner','Diaz','Parker',
    'Cruz','Edwards','Collins','Reyes','Stewart','Morris','Morales','Murphy',
    'Cook','Rogers','Gutierrez','Ortiz','Morgan','Cooper','Peterson','Bailey',
    'Reed','Kelly','Howard','Ramos','Kim','Cox','Ward','Richardson',
    'Watson','Brooks','Chavez','Wood','James','Bennett','Gray','Mendoza',
    'Ruiz','Hughes','Price','Alvarez','Castillo','Sanders','Patel','Myers',
    'Long','Ross','Foster','Jimenez'
);

my @cities = (
    'New York','Los Angeles','Chicago','Houston','Phoenix','Philadelphia','San Antonio','San Diego',
    'Dallas','Austin','San Jose','Jacksonville','Fort Worth','Columbus','Charlotte','Indianapolis',
    'San Francisco','Seattle','Denver','Nashville','Oklahoma City','El Paso','Washington','Boston',
    'Las Vegas','Portland','Memphis','Louisville','Baltimore','Milwaukee','Albuquerque','Tucson',
    'Fresno','Sacramento','Mesa','Kansas City','Atlanta','Omaha','Colorado Springs','Raleigh',
    'Long Beach','Virginia Beach','Miami','Oakland','Minneapolis','Tampa','Tulsa','Arlington',
    'New Orleans','Cleveland','Bakersfield','Honolulu','Anaheim','Santa Ana','Riverside','Corpus Christi',
    'Lexington','Stockton','St. Louis','St. Paul','Henderson','Pittsburgh','Cincinnati','Anchorage',
    'Greensboro','Plano','Lincoln','Orlando','Irvine','Newark','Toledo','Durham',
    'Chula Vista','Fort Wayne','Jersey City','St. Petersburg','Laredo','Madison','Chandler','Buffalo',
    'Lubbock','Scottsdale','Reno','Glendale','Gilbert','Winston-Salem','North Las Vegas','Norfolk',
    'Chesapeake','Garland','Irving','Hialeah','Fremont','Boise','Richmond','Baton Rouge',
    'Spokane','Des Moines','Tacoma','San Bernardino','Modesto','Fontana','Santa Clarita','Birmingham'
);

my @streets = (
    'Main St','Oak Ave','Elm St','Maple Dr','Cedar Ln','Pine Rd','Birch Blvd','Walnut Way',
    'Cherry Ct','Spruce Cir','Willow Ave','Ash St','Poplar Dr','Hickory Ln','Sycamore Blvd','Magnolia Way',
    'Dogwood Ct','Redwood Cir','Palm Ave','Olive St','Laurel Dr','Locust Ln','Chestnut Blvd','Acacia Way',
    'Jasmine Ct','Lavender Cir','Rose Ave','Lily St','Daisy Dr','Orchid Ln','Ivy Blvd','Violet Way',
    'Sunset Blvd','Ocean Ave','Lake Dr','River Rd','Mountain View','Valley Ln','Forest Ave','Meadow Dr',
    'Park Ave','Broadway','First St','Second Ave','Third St','Fourth Ave','Fifth St','Sixth Ave',
    'Seventh St','Eighth Ave','Ninth St','Tenth Ave','Elmwood Ave','Highland Dr','Westwood Blvd','Eastside Way',
    'Northwood Ct','Southpark Cir','Bayview Ave','Harbor Dr','Coastal Hwy','Riverside Dr','Springfield Ave','Fairview Blvd'
);

my @professions = (
    'Software Engineer','Data Scientist','Product Manager','UX Designer','DevOps Engineer','Architect',
    'Teacher','Nurse','Doctor','Lawyer','Accountant','Chef','Electrician','Plumber','Carpenter',
    'Journalist','Photographer','Graphic Designer','Marketing Manager','Sales Associate','Consultant',
    'Professor','Researcher','Biologist','Chemist','Physicist','Astronomer','Geologist',
    'Pilot','Flight Attendant','Train Conductor','Truck Driver','Bus Driver','Mechanic',
    'Musician','Actor','Director','Producer','Screenwriter','Composer','Dancer',
    'Fashion Designer','Interior Designer','Jewelry Designer','Florist','Baker','Butcher',
    'Firefighter','Police Officer','Paramedic','Lifeguard','Security Guard','Detective',
    'Pharmacist','Veterinarian','Dentist','Surgeon','Psychologist','Therapist','Nutritionist',
    'Librarian','Curator','Museum Guide','Archivist','Translator','Editor','Proofreader',
    'Real Estate Agent','Insurance Agent','Banker','Financial Advisor','Economist','Auditor',
    'Web Developer','Mobile Developer','Game Developer','Database Administrator','Network Engineer',
    'Civil Engineer','Mechanical Engineer','Electrical Engineer','Chemical Engineer','Aerospace Engineer',
    'HR Manager','Recruiter','Trainer','CEO','CTO','CFO','COO','Entrepreneur',
    'Farmer','Gardener','Veterinary Assistant','Zookeeper','Park Ranger','Environmental Scientist'
);

my @companies = (
    'TechNova','DataStream','CloudPeak','QuantumLeap','NexGen','AlphaCore','BetaWave','GammaSys',
    'DeltaSoft','OmegaTech','Polaris Inc','Orion Corp','Andromeda Ltd','Sirius Systems','Vega Global',
    'Apex Solutions','Summit Technologies','Crest Analytics','Pinnacle Software','Zenith Digital',
    'Meridian Health','Aurora Medical','Cascade Bio','Evergreen Pharma','Pioneer Diagnostics',
    'Horizon Financial','Summit Capital','Peak Investments','Crest Wealth','Valley Trust',
    'BrightPath Education','LearnSphere','EduCore','MindGrowth','SkillForge',
    'GreenField Agriculture','PureHarvest','EarthWise','NatureFirst','Bloom Organics',
    'CyberShield Security','SafeNet','Guardian Systems','SecureTech','Fortress Cyber',
    'Velocity Logistics','CargoSync','TransGlobal','FreightWorks','ShipFast',
    'Vertex Construction','BuildRight','Foundation Corp','ArchStone','SolidBase',
    'Stellar Games','PixelCraft','GameVision','FunForge','PlayDynamic',
    'AquaPure Water','CleanEnergy Co','EcoSmart','Solaris Power','WindForce Energy',
    'CityScape Realty','HomeFinders','PrimeLocation','UrbanNest','PropertyFirst'
);

my @phone_prefixes = ('555','555','555','555','888','877','866','800');

# ---------------------------------------------------------------------------
# Helper: random element from array
# ---------------------------------------------------------------------------
srand(time() ^ $$ ^ rand(999999));
sub _rand_elem {
    my ($arr) = @_;
    return $arr->[int(rand(scalar @$arr))];
}

# ---------------------------------------------------------------------------
# Helper: generate random phone number
# ---------------------------------------------------------------------------
sub _rand_phone {
    my $p = _rand_elem(\@phone_prefixes);
    my $n1 = int(rand(900)) + 100;
    my $n2 = int(rand(9000)) + 1000;
    return "$p-$n1-$n2";
}

# ---------------------------------------------------------------------------
# Helper: generate email from name
# ---------------------------------------------------------------------------
sub _email_from_name {
    my ($first, $last) = @_;
    my $domain = _rand_elem(['gmail.com','yahoo.com','outlook.com','hotmail.com','proton.me','icloud.com','aol.com','mail.com']);
    my $fmt = int(rand(5));
    if ($fmt == 0)      { return lc("$first.$last\@$domain"); }
    elsif ($fmt == 1)   { return lc("$first$last\@$domain"); }
    elsif ($fmt == 2)   { return lc(substr($first,0,1) . $last . int(rand(100)) . "\@$domain"); }
    elsif ($fmt == 3)   { return lc("$first.$last" . int(rand(99)+1) . "\@$domain"); }
    else                { return lc("$first" . int(rand(99)) . "\@$domain"); }
}

# ---------------------------------------------------------------------------
# Generate fake person
# ---------------------------------------------------------------------------
sub _gen_user {
    my $first = _rand_elem(\@first_names);
    my $last  = _rand_elem(\@last_names);
    my $city  = _rand_elem(\@cities);
    my $prof  = _rand_elem(\@professions);
    my $phone = _rand_phone();
    my $email = _email_from_name($first, $last);
    my $street_num = int(rand(9000)) + 100;
    my $street = _rand_elem(\@streets);
    my $zip = sprintf("%05d", int(rand(90000)) + 10000);
    return {
        name           => "$first $last",
        first_name     => $first,
        last_name      => $last,
        email          => $email,
        phone          => $phone,
        city           => $city,
        street_address => "$street_num $street",
        zip_code       => $zip,
        profession     => $prof,
        age            => int(rand(50)) + 18,
    };
}

# ---------------------------------------------------------------------------
# Generate fake company
# ---------------------------------------------------------------------------
sub _gen_company {
    my $company = _rand_elem(\@companies);
    my $city    = _rand_elem(\@cities);
    my $street_num = int(rand(900)) + 100;
    my $street     = _rand_elem(\@streets);
    my $phone      = _rand_phone();
    my $domain     = lc($company) =~ s/[^a-z0-9]//gr . '.com';
    my $industry = _rand_elem([
        'Technology','Healthcare','Finance','Education','Agriculture','Construction',
        'Energy','Transportation','Retail','Manufacturing','Media','Real Estate'
    ]);
    return {
        company_name    => $company,
        industry        => $industry,
        address         => "$street_num $street, $city",
        city            => $city,
        phone           => $phone,
        email           => "info\@$domain",
        website         => "https://www.$domain",
        employee_count  => int(rand(9000)) + 100,
        founded_year    => int(rand(50)) + 1970,
    };
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
if ($type eq 'user' || $type eq 'person') {
    return _gen_user();
}
elsif ($type eq 'company') {
    return _gen_company();
}
elsif ($type eq 'address') {
    my $city  = _rand_elem(\@cities);
    my $street_num = int(rand(9000)) + 100;
    my $street     = _rand_elem(\@streets);
    my $zip = sprintf("%05d", int(rand(90000)) + 10000);
    return {
        street_address => "$street_num $street",
        city           => $city,
        zip_code       => $zip,
    };
}
elsif ($type eq 'all') {
    my $user = _gen_user();
    my $company = _gen_company();
    return {
        user    => $user,
        company => $company,
    };
}
else {
    return { error => "Unknown type '$type'. Supported types: user, person, company, address, all" };
}